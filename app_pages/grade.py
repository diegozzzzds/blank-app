import streamlit as st

from essay_coach import ai, prompts, state, ui
from essay_coach.rubrics import ESSAY_TYPES, RUBRICS, normalize_scores
from essay_coach.schemas import GradingResult

proj = state.project()
fields = proj["fields"]

st.title("✍️ 写作与 AI 批改")
st.caption("写完初稿后提交，AI 会按评分标准打分、在原文中批注，并给出按优先级排序的修改任务。")

prompt = state.bound(st.text_area, "essay_prompt", "作文题目", default="", height=80,
                     placeholder="粘贴英文题目（可以与大纲教练中的题目相同）")
c1, c2 = st.columns(2)
with c1:
    essay_type = state.bound(st.selectbox, "essay_type", "文章类型", default=ESSAY_TYPES[0], options=ESSAY_TYPES)
with c2:
    rubric_key = state.bound(st.selectbox, "rubric", "评分标准", default="general", options=list(RUBRICS),
                             format_func=lambda k: RUBRICS[k]["name"])

with st.expander("📏 查看评分标准"):
    for c in RUBRICS[rubric_key]["criteria"]:
        st.markdown(f"- **{c['name']}**（{c['max']} 分）：{c['desc']}")

has_outline = bool(fields.get("outline_thesis", "").strip())
if has_outline:
    write_col, outline_col = st.columns([2, 1])
    with outline_col:
        with st.container(border=True):
            st.markdown("**🧭 我的大纲**")
            st.text(prompts.outline_text(fields))
else:
    write_col = st.container()

with write_col:
    essay = state.bound(st.text_area, "essay_text", "我的文章（段落之间空一行）", default="", height=420,
                        placeholder="Write or paste your essay here...")
    target = int(fields.get("target_words", 300) or 300)
    count = ui.word_count(essay)
    st.caption(f"英文词数：**{count}** / 目标 {target}")

if not has_outline:
    st.caption("💡 还没有大纲？先去“大纲教练”规划一下，写起来会更顺。")

if ui.require_ai():
    if proj["drafts"]:
        st.info(f"你已经提交过 {len(proj['drafts'])} 稿。修改后的稿件建议到“修改工坊”提交，"
                "AI 会对比新旧两稿并检查修改任务。在这里提交会作为一篇新文章重新批改。")
    if st.button("🧑‍🏫 提交批改", type="primary", disabled=count < 30, help="至少需要 30 个英文单词"):
        system, user = prompts.grading_request(rubric_key, prompt, essay_type, essay)
        result = ui.run_ai("老师正在认真批改，通常需要 30–90 秒…", ai.structured, system, user, GradingResult)
        if result:
            grading = result.model_dump()
            grading["criteria"], grading["overall_score"] = normalize_scores(rubric_key, grading["criteria"])
            state.add_draft(essay, rubric_key, grading)
            state.reset_field("revision_text", essay)  # 修改工坊的编辑区从这一稿开始

draft = state.latest_draft()
if draft:
    st.divider()
    head, dl = st.columns([3, 1], vertical_alignment="center")
    head.subheader(f"📄 第 {draft['version']} 稿批改报告")
    dl.download_button("⬇️ 下载报告（Markdown）", ui.report_markdown(draft),
                       file_name=f"essay_report_v{draft['version']}.md", mime="text/markdown", width="stretch")
    previous = proj["drafts"][-2] if len(proj["drafts"]) > 1 else None
    ui.render_grading(draft, previous, key=f"grade_v{draft['version']}")
    st.divider()
    st.markdown("**下一步：** 对照修改任务自己修改，然后到修改工坊提交新稿，看看分数有没有提升。")
    st.page_link("app_pages/revise.py", label="去修改工坊", icon="🔁")
