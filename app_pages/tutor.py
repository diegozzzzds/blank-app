import streamlit as st

from essay_coach import prompts, state, ui

proj = state.project()
fields = proj["fields"]
chat = proj["chat"]

st.title("💬 写作导师")
st.caption("像和老师面对面一样提问。导师会多问你几个问题，帮你自己想清楚。")

left, right = st.columns([3, 1], vertical_alignment="center")
with left:
    share = st.toggle("让导师看到我当前的题目、大纲和最新稿件", value=True)
with right:
    if st.button("🧹 新对话", width="stretch", disabled=not chat):
        chat.clear()
        st.rerun()


def _context() -> str:
    if not share:
        return "（学生没有分享当前的文章材料。）"
    parts = []
    if fields.get("essay_prompt", "").strip():
        parts.append(f"<essay_prompt>\n{fields['essay_prompt']}\n</essay_prompt>")
    if fields.get("outline_thesis", "").strip():
        parts.append(f"<student_outline>\n{prompts.outline_text(fields)}\n</student_outline>")
    if draft := state.latest_draft():
        tasks = "\n".join(f"- {t['title']}" for t in draft["grading"]["revision_tasks"])
        parts.append(f"<latest_draft version=\"{draft['version']}\">\n{draft['text']}\n</latest_draft>\n"
                     f"<latest_revision_tasks>\n{tasks}\n</latest_revision_tasks>")
    if not parts:
        return "（学生还没有写题目、大纲或稿件。）"
    return "学生当前的写作材料（仅供参考，回答学生的问题时可以引用）：\n" + "\n".join(parts)


STARTERS = [
    "我不知道这道题该怎么切入",
    "我的 thesis 够好吗？",
    "怎么让主体段的分析更深入？",
    "我总是写 Chinglish，怎么改？",
    "批改里的第一个修改任务我看不懂",
]

if not chat:
    with st.chat_message("assistant", avatar="🧑‍🏫"):
        st.markdown("你好！我是你的写作导师。今天想聊什么？可以直接提问，也可以点下面的话题开始。")
    starter = st.pills("话题", STARTERS, label_visibility="collapsed", key="starter_pill")
else:
    starter = None

for msg in chat:
    with st.chat_message(msg["role"], avatar="🧑‍🏫" if msg["role"] == "assistant" else "🧑‍🎓"):
        st.markdown(msg["content"])

typed = st.chat_input("输入你的问题…", disabled=not ui.require_ai())
question = typed or starter
if question:
    chat.append({"role": "user", "content": question})
    with st.chat_message("user", avatar="🧑‍🎓"):
        st.markdown(question)
    with st.chat_message("assistant", avatar="🧑‍🏫"):
        reply = ui.stream_ai(st.empty(), prompts.tutor_system(_context()),
                             [{"role": m["role"], "content": m["content"]} for m in chat], 8000)
    if reply:
        chat.append({"role": "assistant", "content": reply})
        st.rerun()
    # 请求失败：撤回这条提问，保留错误提示，方便重试
    chat.pop()
    st.session_state.pop("starter_pill", None)
