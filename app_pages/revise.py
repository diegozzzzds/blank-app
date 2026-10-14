import altair as alt
import streamlit as st

from essay_coach import ai, prompts, state, ui
from essay_coach.rubrics import ESSAY_TYPES, RUBRICS, format_score, normalize_scores
from essay_coach.schemas import RevisionResult

proj = state.project()
fields = proj["fields"]
drafts = proj["drafts"]

st.title("🔁 修改工坊")
st.caption("对照修改任务自己改 → 卡住时请 AI 精修某一段 → 提交新稿，AI 检查每个任务完成得怎么样。")

latest = state.latest_draft()
if latest is None:
    st.info("还没有批改过的稿件。先去写一篇初稿并提交批改吧。")
    st.page_link("app_pages/grade.py", label="去写初稿", icon="✍️")
    st.stop()

rubric_key = latest["rubric"]
rubric = RUBRICS[rubric_key]

# ---------- 分数趋势 ----------
same_rubric = [d for d in drafts if d["rubric"] == rubric_key]
if len(same_rubric) > 1:
    st.subheader("📈 分数变化")
    data = [{"稿件": f"第 {d['version']} 稿", "版本": d["version"], "总分": d["grading"]["overall_score"]}
            for d in same_rubric]
    chart = (
        alt.Chart(alt.Data(values=data))
        .mark_line(point=alt.OverlayMarkDef(size=90, filled=True), strokeWidth=2)
        .encode(
            x=alt.X("版本:O", title="稿件版本", axis=alt.Axis(labelAngle=0)),
            y=alt.Y("总分:Q", title=f"总分（满分 {rubric['max']}）", scale=alt.Scale(domain=[0, rubric["max"]])),
            tooltip=[alt.Tooltip("稿件:N"), alt.Tooltip("总分:Q")],
        )
        .properties(height=220)
    )
    st.altair_chart(chart, width="stretch")

# ---------- 修改区 ----------
st.subheader(f"✏️ 修改第 {latest['version']} 稿")
tasks_col, edit_col = st.columns([1, 2])

with tasks_col:
    st.markdown("**✅ 修改任务清单**")
    for i, t in enumerate(latest["grading"]["revision_tasks"]):
        st.checkbox(f"**{t['title']}**", key=f"task_v{latest['version']}_{i}", help=t["detail"])
        st.caption(t["detail"])
    majors = [a for a in latest["grading"]["annotations"] if a["severity"] == "major"]
    if majors:
        with st.expander(f"🔴 重要批注（{len(majors)}）"):
            for a in majors:
                st.markdown(f"> {a['quote']}\n\n{a['issue']}\n\n**建议：** {a['suggestion']}")
                st.divider()

with edit_col:
    new_text = state.bound(st.text_area, "revision_text", "修改稿", default=latest["text"], height=460)
    st.caption(f"英文词数：**{ui.word_count(new_text)}**（上一稿 {ui.word_count(latest['text'])}）")
    st.button(f"↩️ 恢复为第 {latest['version']} 稿原文",
              on_click=state.set_field, args=("revision_text", latest["text"]))

# ---------- 段落精修 ----------
with st.expander("🔬 段落精修：请 AI 帮你看一段", expanded=False):
    _, paragraphs = prompts.number_paragraphs(new_text)
    if not paragraphs:
        st.caption("修改稿是空的。")
    else:
        idx = st.selectbox("选择段落", range(len(paragraphs)),
                           format_func=lambda i: f"P{i + 1} · {paragraphs[i][:60]}{'…' if len(paragraphs[i]) > 60 else ''}")
        guided = st.session_state.get("teach_mode", "").startswith("引导式")
        mode = st.radio("我想要", ["💡 只给提示，我自己改", "📝 给我看示范改写"], index=0 if guided else 1,
                        horizontal=True)
        question = st.text_input("具体想问什么？（可选）", placeholder="e.g. 这段的分析好像不够，怎么加强？")
        clicked = ui.require_ai() and st.button("请老师看看这段")
        placeholder = st.empty()
        if clicked:
            system, messages = prompts.paragraph_coach_request(
                fields.get("essay_prompt", ""), new_text, idx + 1, paragraphs[idx],
                want_example=mode.startswith("📝"), question=question)
            if reply := ui.stream_ai(placeholder, system, messages, 8000):
                st.session_state.paragraph_reply = (idx, reply)
        elif (saved := st.session_state.get("paragraph_reply")) and saved[0] == idx:
            placeholder.markdown(saved[1])

# ---------- 提交修改稿 ----------
unchanged = new_text.strip() == latest["text"].strip()
if ui.require_ai():
    if st.button("📤 提交修改稿，看看进步了多少", type="primary", disabled=unchanged or ui.word_count(new_text) < 30,
                 help="修改稿和上一稿相同时不能提交" if unchanged else None):
        essay_type = fields.get("essay_type", ESSAY_TYPES[0])
        system, user = prompts.revision_request(rubric_key, fields.get("essay_prompt", ""), essay_type,
                                                latest, new_text)
        result = ui.run_ai("老师正在对比两稿并重新批改，通常需要 1–2 分钟…", ai.structured, system, user, RevisionResult)
        if result:
            data = result.model_dump()
            grading = data["grading"]
            grading["criteria"], grading["overall_score"] = normalize_scores(rubric_key, grading["criteria"])
            state.add_draft(new_text, rubric_key, grading, data["comparison"])
            st.rerun()

# ---------- 最新一稿的反馈 ----------
if latest.get("comparison"):
    st.divider()
    previous = drafts[-2]
    st.subheader(f"📄 第 {latest['version']} 稿 vs 第 {previous['version']} 稿")
    ui.render_comparison(latest["comparison"])
    with st.expander("🔀 查看文字改动（红色删除 / 绿色新增）"):
        st.html(ui.word_diff_html(previous["text"], latest["text"]))
    with st.expander(f"📋 第 {latest['version']} 稿完整批改报告", expanded=True):
        ui.render_grading(latest, previous, key=f"revise_v{latest['version']}")
        st.download_button("⬇️ 下载报告（Markdown）", ui.report_markdown(latest),
                           file_name=f"essay_report_v{latest['version']}.md", mime="text/markdown")

# ---------- 历史稿件 ----------
if len(drafts) > 1:
    st.divider()
    with st.expander("🗂️ 历史稿件"):
        v = st.selectbox("选择版本", [d["version"] for d in drafts][::-1],
                         format_func=lambda v: f"第 {v} 稿 · {drafts[v - 1]['created']} · "
                                               f"{format_score(drafts[v - 1]['rubric'], drafts[v - 1]['grading']['overall_score'])} 分")
        d = drafts[v - 1]
        st.text(d["text"])
        st.download_button("⬇️ 下载这一稿的报告", ui.report_markdown(d), file_name=f"essay_report_v{v}.md",
                           mime="text/markdown", key=f"dl_hist_{v}")
