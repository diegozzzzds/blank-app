"""通用界面组件：批改报告、原文高亮、修改对比、AI 状态提示。"""

import difflib
import html
import re

import streamlit as st

from . import ai
from .rubrics import RUBRICS, format_score

CATEGORIES = {
    "grammar": ("语法", "rgba(239, 68, 68, 0.22)"),
    "vocabulary": ("词汇", "rgba(245, 158, 11, 0.26)"),
    "logic": ("逻辑", "rgba(139, 92, 246, 0.24)"),
    "structure": ("结构", "rgba(59, 130, 246, 0.24)"),
    "evidence": ("论据", "rgba(16, 185, 129, 0.24)"),
    "style": ("文风", "rgba(236, 72, 153, 0.22)"),
    "mechanics": ("拼写标点", "rgba(107, 114, 128, 0.28)"),
}
SEVERITY = {"major": "🔴 重要", "minor": "🟡 次要", "suggestion": "🔵 建议"}
RATING = {"strong": "✅ 很好", "ok": "🟡 可以更好", "weak": "🔴 需要修改"}
TASK_STATUS = {"done": "✅ 已完成", "partial": "🟡 部分完成", "not_done": "❌ 未完成"}


def word_count(text: str) -> int:
    return len(re.findall(r"[A-Za-z]+(?:['’-][A-Za-z]+)*", text))


def require_ai() -> bool:
    if ai.is_ready():
        return True
    st.info("🔑 这个功能需要 AI。请先在左侧边栏填写 Anthropic API Key（课程讲解和小测验不需要）。")
    return False


def run_ai(spinner: str, fn, *args, **kwargs):
    """执行 AI 调用，出错时显示中文提示并返回 None。"""
    try:
        with st.spinner(spinner):
            return fn(*args, **kwargs)
    except ai.AIError as e:
        st.error(str(e))
        return None


def stream_ai(placeholder, *args, **kwargs) -> str | None:
    try:
        return ai.stream_markdown(placeholder, *args, **kwargs)
    except ai.AIError as e:
        st.error(str(e))
        return None


def _locate(text: str, annotations: list[dict]) -> list[tuple[int, int, int]]:
    """为每条批注在原文中找到不重叠的位置，返回 (start, end, 批注序号)。"""
    spans: list[tuple[int, int, int]] = []
    for idx, ann in enumerate(annotations):
        words = ann["quote"].strip().strip("\"'“”").split()
        if not words:
            continue
        # AI 看到的段落合并了空白，所以允许引用中的空格匹配原文中的任意空白（含换行）
        pattern = re.compile(r"\s+".join(map(re.escape, words)))
        for match in pattern.finditer(text):
            pos, end = match.span()
            if all(end <= s or pos >= e for s, e, _ in spans):
                spans.append((pos, end, idx))
                break
    return sorted(spans)


def highlighted_essay_html(text: str, annotations: list[dict]) -> tuple[str, set[int]]:
    spans = _locate(text, annotations)
    out, cursor = [], 0
    for start, end, idx in spans:
        ann = annotations[idx]
        label, color = CATEGORIES.get(ann["category"], ("其他", "rgba(107,114,128,0.25)"))
        # title 里的换行要转义，否则会被下面的 \n → <br> 替换破坏
        tip = html.escape(f"[{label}] {ann['issue']}\n→ {ann['suggestion']}", quote=True).replace("\n", "&#10;")
        out.append(html.escape(text[cursor:start]))
        weight = "border-bottom: 2px solid rgba(239,68,68,0.9);" if ann["severity"] == "major" else ""
        out.append(
            f'<mark title="{tip}" style="background:{color};{weight}color:inherit;'
            f'padding:0 2px;border-radius:3px;">{html.escape(text[start:end])}'
            f'<sup style="font-weight:600;padding-left:1px;">{idx + 1}</sup></mark>'
        )
        cursor = end
    out.append(html.escape(text[cursor:]))
    body = "".join(out).replace("\n", "<br>")
    return (f'<div style="line-height:1.9;font-size:1.02rem;padding:0.75rem 1rem;'
            f'border-radius:0.5rem;border:1px solid rgba(128,128,128,0.3);">{body}</div>'), {i for *_, i in spans}


def legend() -> None:
    chips = " ".join(
        f'<span style="background:{color};padding:1px 8px;border-radius:10px;margin-right:4px;">{label}</span>'
        for label, color in CATEGORIES.values()
    )
    st.html(f'<div style="font-size:0.85rem;">{chips} · 鼠标悬停高亮处查看批注</div>')


def word_diff_html(old: str, new: str) -> str:
    """词级别对比：删除的标红划线，新增的标绿。"""
    # 词连同其后的空白作为一个单位，这样连续改动会合并成一整段删除 + 一整段新增
    tokenize = lambda s: re.findall(r"\S+\s*|\s+", s)  # noqa: E731
    a, b = tokenize(old), tokenize(new)
    out = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes():
        if op == "equal":
            out.append(html.escape("".join(a[i1:i2])))
            continue
        if op in ("delete", "replace"):
            out.append('<del style="background:rgba(239,68,68,0.22);color:inherit;">'
                       f'{html.escape("".join(a[i1:i2]))}</del>')
        if op in ("insert", "replace"):
            out.append('<ins style="background:rgba(16,185,129,0.25);color:inherit;text-decoration:none;">'
                       f'{html.escape("".join(b[j1:j2]))}</ins>')
    body = "".join(out).replace("\n", "<br>")
    return (f'<div style="line-height:1.9;padding:0.75rem 1rem;border-radius:0.5rem;'
            f'border:1px solid rgba(128,128,128,0.3);">{body}</div>')


def render_scores(draft: dict, previous: dict | None = None) -> None:
    rubric = RUBRICS[draft["rubric"]]
    grading = draft["grading"]
    cols = st.columns([1.2, 1, 2.5])
    delta, delta_color = None, "normal"
    if previous and previous["rubric"] == draft["rubric"]:
        diff = grading["overall_score"] - previous["grading"]["overall_score"]
        delta = format_score(draft["rubric"], diff) if diff else "与上一稿持平"
        delta_color = "normal" if diff else "off"
    cols[0].metric("总分", f"{format_score(draft['rubric'], grading['overall_score'])} / {rubric['max']}",
                   delta=delta, delta_color=delta_color)
    cols[1].metric("水平", grading["level_label"])
    cols[2].markdown(f"**总评**\n\n{grading['summary']}")

    st.markdown("#### 📊 分项得分")
    for c in grading["criteria"]:
        with st.container(border=True):
            left, right = st.columns([3, 1])
            left.markdown(f"**{c['name']}**")
            right.markdown(f"**{format_score(draft['rubric'], c['score'])} / {c['max_score']}**")
            st.progress(min(c["score"] / c["max_score"], 1.0) if c["max_score"] else 0.0)
            st.caption(c["comment"])


def render_annotations(text: str, annotations: list[dict], key: str) -> None:
    st.markdown("#### 🖍️ 原文批注")
    essay_html, located = highlighted_essay_html(text, annotations)
    legend()
    st.html(essay_html)

    st.markdown("#### 📝 批注详情")
    options = [k for k in CATEGORIES if any(a["category"] == k for a in annotations)]
    chosen = st.pills("按类型筛选", options, selection_mode="multi", default=options,
                      format_func=lambda k: CATEGORIES[k][0], key=f"{key}_filter")
    for i, ann in enumerate(annotations):
        if ann["category"] not in (chosen or []):
            continue
        label = CATEGORIES.get(ann["category"], ("其他",))[0]
        with st.container(border=True):
            mark = "" if i in located else "（原文中未精确定位）"
            st.markdown(f"**{i + 1}.** {SEVERITY[ann['severity']]} · {label} {mark}")
            st.markdown(f"> {ann['quote']}")
            st.markdown(f"**问题：** {ann['issue']}")
            st.markdown(f"**建议：** {ann['suggestion']}")


def render_grading(draft: dict, previous: dict | None = None, key: str = "report") -> None:
    grading = draft["grading"]
    render_scores(draft, previous)

    if grading["strengths"]:
        st.markdown("#### 🌟 做得好的地方")
        for s in grading["strengths"]:
            st.markdown(f"- {s}")

    render_annotations(draft["text"], grading["annotations"], key)

    st.markdown("#### 🧭 逐段反馈（反向大纲）")
    for p in grading["paragraph_feedback"]:
        with st.expander(f"P{p['paragraph']} · {p['role']} — {p['main_idea']}"):
            st.markdown(p["feedback"])

    render_tasks(grading["revision_tasks"])


def render_tasks(tasks: list[dict]) -> None:
    st.markdown("#### ✅ 修改任务（按优先级）")
    for i, t in enumerate(tasks, 1):
        label = CATEGORIES.get(t["focus"], ("其他",))[0]
        st.markdown(f"**{i}. {t['title']}** `{label}`\n\n{t['detail']}")


def render_comparison(comparison: dict) -> None:
    st.markdown("#### 🔍 修改效果")
    st.markdown(comparison["overall"])
    cols = st.columns(2)
    with cols[0]:
        st.markdown("**进步**")
        for item in comparison["improvements"] or ["（暂无）"]:
            st.markdown(f"- {item}")
    with cols[1]:
        st.markdown("**新问题 / 退步**")
        for item in comparison["regressions"] or ["没有发现明显退步 👍"]:
            st.markdown(f"- {item}")
    st.markdown("**上一版修改任务完成情况**")
    for t in comparison["task_checks"]:
        st.markdown(f"- {TASK_STATUS[t['status']]} **{t['task']}** — {t['comment']}")


def report_markdown(draft: dict) -> str:
    rubric = RUBRICS[draft["rubric"]]
    g = draft["grading"]
    lines = [
        f"# EssayCoach 批改报告 · 第 {draft['version']} 稿",
        f"_{draft['created']} · {rubric['name']}_",
        "",
        f"**总分：{format_score(draft['rubric'], g['overall_score'])} / {rubric['max']}**（{g['level_label']}）",
        "",
        g["summary"],
        "",
        "## 分项得分",
    ]
    for c in g["criteria"]:
        lines += [f"- **{c['name']}**：{format_score(draft['rubric'], c['score'])} / {c['max_score']}",
                  f"  - {c['comment']}"]
    lines += ["", "## 做得好的地方"] + [f"- {s}" for s in g["strengths"]]
    lines += ["", "## 批注"]
    for i, a in enumerate(g["annotations"], 1):
        lines += [f"{i}. [{CATEGORIES.get(a['category'], ('其他',))[0]} · {SEVERITY[a['severity']]}] “{a['quote']}”",
                  f"   - 问题：{a['issue']}", f"   - 建议：{a['suggestion']}"]
    lines += ["", "## 修改任务"]
    for i, t in enumerate(g["revision_tasks"], 1):
        lines.append(f"{i}. **{t['title']}**：{t['detail']}")
    if draft.get("comparison"):
        c = draft["comparison"]
        lines += ["", "## 与上一稿对比", c["overall"], ""] + [f"- ✅ {x}" for x in c["improvements"]]
        lines += [f"- ⚠️ {x}" for x in c["regressions"]]
    lines += ["", "## 原文", "", draft["text"]]
    return "\n".join(lines)
