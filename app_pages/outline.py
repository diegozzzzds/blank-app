import streamlit as st

from essay_coach import ai, prompts, state, ui
from essay_coach.rubrics import ESSAY_TYPES
from essay_coach.schemas import Brainstorm, ModelOutline, OutlineReview

proj = state.project()
fields = proj["fields"]

st.title("🧭 大纲教练")
st.caption("先拆题、头脑风暴，再自己搭大纲，让 AI 逐部分审阅。想清楚再动笔，写作会顺利得多。")

# ---------- 第 1 步：题目 ----------
st.subheader("① 题目与要求")
prompt = state.bound(st.text_area, "essay_prompt", "作文题目（英文原题）", default="", height=100,
                     placeholder="e.g. Some people believe that zoos should be closed. To what extent do you agree or disagree?")
c1, c2 = st.columns(2)
with c1:
    essay_type = state.bound(st.selectbox, "essay_type", "文章类型", default=ESSAY_TYPES[0], options=ESSAY_TYPES)
with c2:
    words = state.bound(st.number_input, "target_words", "目标字数（词）", default=300,
                        min_value=100, max_value=2000, step=50)

# ---------- 第 2 步：头脑风暴 ----------
st.subheader("② 拆题与头脑风暴")
st.caption("AI 只提供角度和问题，具体立场和论据由你自己决定。")
if ui.require_ai() and st.button("🧠 帮我拆题和头脑风暴", disabled=not prompt.strip()):
    system, user = prompts.brainstorm_request(prompt, essay_type, int(words))
    result = ui.run_ai("正在分析题目…", ai.structured, system, user, Brainstorm, 8000)
    if result:
        proj["brainstorm"] = result.model_dump()

if bs := proj["brainstorm"]:
    with st.container(border=True):
        st.markdown(f"**🔎 题目拆解：** {bs['prompt_analysis']}")
        if bs["key_terms"]:
            st.markdown("**🔑 关键词：** " + "、".join(f"`{t}`" for t in bs["key_terms"]))
        st.markdown("**🧭 可选的立场 / 角度**")
        cols = st.columns(len(bs["angles"]) or 1)
        for col, angle in zip(cols, bs["angles"]):
            with col.container(border=True):
                st.markdown(f"**{angle['stance']}**")
                st.markdown(f"核心理由：{angle['core_reason']}")
                st.markdown("\n".join(f"- {e}" for e in angle["evidence_ideas"]))
        left, right = st.columns(2)
        with left:
            st.markdown("**🤔 想一想**")
            st.markdown("\n".join(f"- {q}" for q in bs["guiding_questions"]))
        with right:
            st.markdown("**⚠️ 容易失分的地方**")
            st.markdown("\n".join(f"- {p}" for p in bs["pitfalls"]))

state.bound(st.text_area, "brainstorm_notes", "我的想法笔记（选好立场、记下论据）", default="", height=100)

# ---------- 第 3 步：搭大纲 ----------
st.subheader("③ 搭建你的大纲")
st.caption("用英文写要点即可，不需要完整句子（thesis 和 topic sentence 建议写完整）。参考第 2、3、4 课。")
state.bound(st.text_input, "outline_thesis", "🎯 Thesis（论点句）", default="",
            placeholder="Although ..., I believe ... because ... and ...")
state.bound(st.text_input, "outline_hook", "🚪 开头：Hook 与背景", default="",
            placeholder="e.g. a surprising contrast about zoos then vs now")
body_count = state.bound(st.number_input, "outline_body_count", "主体段数量", default=3, min_value=1, max_value=5)
for i in range(1, int(body_count) + 1):
    with st.container(border=True):
        st.markdown(f"**主体段 {i}**")
        state.bound(st.text_input, f"outline_body{i}_point", "Topic sentence（中心论点）", default="")
        a, b = st.columns(2)
        with a:
            state.bound(st.text_area, f"outline_body{i}_evidence", "Evidence（论据）", default="", height=80)
        with b:
            state.bound(st.text_area, f"outline_body{i}_analysis", "Analysis（这个论据怎样证明论点？）",
                        default="", height=80)
state.bound(st.text_area, "outline_counter", "⚖️ 反方观点与反驳（可选）", default="", height=80)
state.bound(st.text_area, "outline_conclusion", "🏁 结尾：重申 + 升华", default="", height=80)

outline = prompts.outline_text(fields)
filled = bool(fields.get("outline_thesis", "").strip())

# ---------- 第 4 步：AI 审阅 ----------
st.subheader("④ AI 审阅大纲")
if ui.require_ai() and st.button("📋 请 AI 审阅我的大纲", type="primary", disabled=not (prompt.strip() and filled),
                                 help="需要先填写题目和 thesis"):
    system, user = prompts.outline_review_request(prompt, essay_type, int(words), outline)
    result = ui.run_ai("老师正在审阅大纲…", ai.structured, system, user, OutlineReview, 12000)
    if result:
        proj["outline_review"] = result.model_dump()

if review := proj["outline_review"]:
    with st.container(border=True):
        readiness = min(max(review["readiness"], 0), 100)
        st.progress(readiness / 100, text=f"可以开始写作的成熟度：{readiness} / 100")
        st.markdown(review["overall"])
        st.markdown(f"**🎯 Thesis 检查：** {review['thesis_check']}")
        for sec in review["sections"]:
            with st.expander(f"{ui.RATING[sec['rating']]} · {sec['section']}", expanded=sec["rating"] == "weak"):
                st.markdown(sec["comment"])
                st.markdown(f"**建议：** {sec['suggestion']}")
        if review["logic_issues"]:
            st.markdown("**🧩 逻辑问题**")
            st.markdown("\n".join(f"- {x}" for x in review["logic_issues"]))
        st.markdown("**🤔 完善大纲可以想想：**")
        st.markdown("\n".join(f"- {q}" for q in review["guiding_questions"]))
    st.caption("根据反馈修改大纲后，可以再次审阅。")

# ---------- 第 5 步：示范大纲 ----------
st.subheader("⑤ 对照示范大纲")
st.caption("建议先自己完成并审阅过大纲，再看示范，对比差距收获最大。")
if ui.require_ai() and st.button("👀 生成一份示范大纲", disabled=not prompt.strip()):
    system, user = prompts.model_outline_request(prompt, essay_type, int(words))
    result = ui.run_ai("正在写示范大纲…", ai.structured, system, user, ModelOutline, 8000)
    if result:
        proj["model_outline"] = result.model_dump()

if mo := proj["model_outline"]:
    with st.expander("示范大纲", expanded=True):
        st.markdown(f"**Thesis:** {mo['thesis']}")
        st.markdown(f"**Introduction:** {mo['hook']} — {mo['background']}")
        for i, body in enumerate(mo["body"], 1):
            st.markdown(f"**Body {i}:** {body['topic_sentence']}")
            st.markdown("\n".join(f"  - Evidence: {e}" for e in body["evidence"]))
            st.markdown(f"  - Analysis: {body['analysis']}")
        st.markdown(f"**Counterargument:** {mo['counterargument']}")
        st.markdown(f"**Rebuttal:** {mo['rebuttal']}")
        st.markdown(f"**Conclusion:** {mo['conclusion']}")
        st.markdown("**📌 这份大纲的设计思路**")
        st.markdown("\n".join(f"- {n}" for n in mo["teaching_notes"]))

st.divider()
st.markdown("大纲准备好了？带着它去写初稿吧——写作页面会在旁边显示你的大纲。")
st.page_link("app_pages/grade.py", label="去写初稿", icon="✍️")
