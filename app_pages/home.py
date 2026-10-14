import streamlit as st

from essay_coach import state
from essay_coach.lessons import LESSONS
from essay_coach.rubrics import RUBRICS, format_score

proj = state.project()

st.title("✍️ EssayCoach · AI 英文写作教练")
st.markdown(
    "从**读懂题目**到**改出好文章**：先学方法，再列大纲、动笔写作，"
    "然后让 AI 像老师一样批改，你根据反馈自己修改、再提交对比，直到写好为止。"
)

drafts = proj["drafts"]
c1, c2, c3, c4 = st.columns(4)
c1.metric("已完成课程", f"{len(proj['lessons_done'])} / {len(LESSONS)}")
c2.metric("提交稿件", len(drafts))
if drafts:
    last = drafts[-1]
    c3.metric("最新得分", f"{format_score(last['rubric'], last['grading']['overall_score'])} / "
                          f"{RUBRICS[last['rubric']]['max']}")
    same = [d for d in drafts if d["rubric"] == last["rubric"]]
    gain = same[-1]["grading"]["overall_score"] - same[0]["grading"]["overall_score"]
    c4.metric("修改带来的提升", format_score(last["rubric"], gain) if len(same) > 1 else "—")
else:
    c3.metric("最新得分", "—")
    c4.metric("修改带来的提升", "—")

st.divider()
st.subheader("🗺️ 推荐学习路径")

steps = [
    ("1", "📚 学方法", "9 节微课：读题、论点、结构、PEEL 主体段、开头结尾、反驳、衔接、学术语言、修改策略。"
                     "每课有范例对比、小测验和 AI 点评的练习。", "app_pages/lessons.py", "去上课"),
    ("2", "🧭 列大纲", "输入题目，AI 帮你拆题和头脑风暴；你自己搭大纲，AI 逐部分审阅，最后可以对照示范大纲。",
     "app_pages/outline.py", "去列大纲"),
    ("3", "✍️ 写初稿 + AI 批改", "按评分标准（通用 / 雅思 / AP / 申请文书）打分，原文高亮批注，逐段反馈，"
                              "并给出按优先级排序的修改任务。", "app_pages/grade.py", "去写作"),
    ("4", "🔁 修改再提交", "对照修改任务自己改，可以请 AI 精修某一段（只给提示或给示范）。"
                       "提交新稿后 AI 检查每个任务的完成情况，显示分数变化和修改对比。", "app_pages/revise.py", "去修改"),
    ("5", "💬 随时提问", "卡住了？和写作导师聊聊。它会用提问引导你想清楚，而不是直接替你写。",
     "app_pages/tutor.py", "去提问"),
]
for num, title, desc, page, cta in steps:
    with st.container(border=True):
        left, right = st.columns([5, 1], vertical_alignment="center")
        left.markdown(f"**第 {num} 步 · {title}**\n\n{desc}")
        right.page_link(page, label=cta, icon="➡️")

st.divider()
with st.expander("💡 怎样用 AI 学写作，进步最快？", expanded=not drafts):
    st.markdown(
        """
- **先自己写，再看 AI 反馈。** 先想清楚、写出来，AI 才能帮你找到*你自己的*问题。
- **一次只改最重要的 2–3 个问题。** 修改任务已经按优先级排好，先改论点和结构，再改语言。
- **看不懂就追问。** 在“写作导师”里问“为什么这样不好？”，比直接抄改写有用得多。
- **保持判断。** AI 也会误解你的意思；如果你有理由不采纳某条建议，完全可以不改。
- **左侧边栏**可以设置水平、反馈语言和教学方式。默认的“引导式”不会替你写，适合真正想提高的同学。
"""
    )
