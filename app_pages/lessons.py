import streamlit as st

from essay_coach import ai, prompts, state, ui
from essay_coach.lessons import LESSON_BY_ID, LESSONS
from essay_coach.schemas import ExerciseFeedback

proj = state.project()

st.title("📚 写作课堂")
st.caption("每节课：讲解 → 范例对比 → 小测验 → 练一练（AI 点评）→ 有问题随时问。")

done = set(proj["lessons_done"])
lesson_id = state.bound(
    st.selectbox, "lesson_id", "选择课程", default=LESSONS[0]["id"],
    options=[l["id"] for l in LESSONS],
    format_func=lambda i: f"{'✅' if i in done else LESSON_BY_ID[i]['icon']} {LESSON_BY_ID[i]['title']}",
)
lesson = LESSON_BY_ID[lesson_id]
st.progress(len(done) / len(LESSONS), text=f"课程进度 {len(done)} / {len(LESSONS)}")

st.header(f"{lesson['icon']} {lesson['title']}")
st.info(f"🎯 **学习目标：** {lesson['goal']}")

tab_learn, tab_examples, tab_quiz, tab_practice, tab_ask = st.tabs(
    ["📖 讲解", "🔍 范例对比", "🧩 小测验", "✏️ 练一练", "🙋 提问"]
)

with tab_learn:
    st.markdown(lesson["content"])

with tab_examples:
    for i, ex in enumerate(lesson["examples"], 1):
        st.markdown(f"##### 范例 {i}")
        left, right = st.columns(2)
        with left:
            st.error(f"**❌ 较弱**\n\n{ex['weak']}")
        with right:
            st.success(f"**✅ 较强**\n\n{ex['strong']}")
        st.markdown(f"💡 **为什么？** {ex['why']}")
        st.divider()

with tab_quiz:
    correct = 0
    for i, q in enumerate(lesson["quiz"]):
        with st.container(border=True):
            choice = st.radio(f"**{i + 1}. {q['q']}**", range(len(q["options"])),
                              format_func=lambda k, q=q: q["options"][k], index=None,
                              key=f"quiz_{lesson_id}_{i}")
            if choice is not None:
                if choice == q["answer"]:
                    correct += 1
                    st.success(f"回答正确！{q['explain']}")
                else:
                    st.warning(f"再想想。正确答案是：**{q['options'][q['answer']]}**。{q['explain']}")
    if correct == len(lesson["quiz"]):
        if not st.session_state.get(f"celebrated_{lesson_id}"):
            st.session_state[f"celebrated_{lesson_id}"] = True
            st.balloons()
        st.success("🎉 小测验全对！完成“练一练”后就可以标记本课完成。")

with tab_practice:
    st.markdown(lesson["exercise"]["task"])
    answer = state.bound(st.text_area, f"exercise_{lesson_id}", "你的答案", default="",
                         height=200, placeholder=lesson["exercise"]["placeholder"])
    if ui.require_ai() and st.button("提交给 AI 老师点评", type="primary", disabled=not answer.strip(),
                                     key=f"submit_{lesson_id}"):
        system, user = prompts.exercise_request(lesson, answer)
        result = ui.run_ai("老师正在看你的答案…", ai.structured, system, user, ExerciseFeedback, 8000)
        if result:
            proj["exercise_feedback"][lesson_id] = result.model_dump()

    feedback = proj["exercise_feedback"].get(lesson_id)
    if feedback:
        stars = min(max(feedback["stars"], 1), 5)
        with st.container(border=True):
            st.markdown(f"### {'⭐' * stars}{'☆' * (5 - stars)}　{feedback['verdict']}")
            left, right = st.columns(2)
            with left:
                st.markdown("**👍 做得好**")
                for s in feedback["strengths"] or ["（继续加油）"]:
                    st.markdown(f"- {s}")
            with right:
                st.markdown("**🔧 需要改进**")
                for s in feedback["issues"] or ["没有明显问题"]:
                    st.markdown(f"- {s}")
            st.markdown(f"**➡️ 下一步：** {feedback['next_step']}")
            with st.expander("👀 看示范（建议先根据反馈自己改一遍）"):
                st.markdown(feedback["example"])
                st.caption(feedback["example_note"])
        st.caption("修改后可以再次提交，看看有没有进步。")

    st.divider()
    if lesson_id in done:
        if st.button("↩️ 取消完成标记", key=f"undo_{lesson_id}"):
            proj["lessons_done"].remove(lesson_id)
            st.rerun()
    elif st.button("✅ 我学会了，标记本课完成", key=f"done_{lesson_id}"):
        proj["lessons_done"].append(lesson_id)
        st.rerun()

with tab_ask:
    st.markdown("对这节课有不明白的地方？直接问老师。例如：*“thesis 一定要放在第一段最后吗？”*")
    question = state.bound(st.text_area, f"ask_{lesson_id}", "你的问题", default="", height=100)
    answer_key = f"lesson_answer_{lesson_id}"
    clicked = ui.require_ai() and st.button("提问", disabled=not question.strip(), key=f"ask_btn_{lesson_id}")
    placeholder = st.empty()
    if clicked:
        reply = ui.stream_ai(placeholder, prompts.lesson_question_system(lesson),
                             [{"role": "user", "content": question}], 8000)
        if reply:
            st.session_state[answer_key] = reply
    elif st.session_state.get(answer_key):
        placeholder.markdown(st.session_state[answer_key])
