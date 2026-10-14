import time

import streamlit as st

from essay_coach import ai, drills, mastery, store, ui
from essay_coach.items import Item, shuffled_order
from essay_coach.skills import AUTO_GRADED, KCS

progress = store.progress()
ss = st.session_state

st.title("🎯 刷题")
st.caption("每题先自己做，答错再看提示，最后才看答案。只有独立做对的题才算进掌握度。做错的技能过几题会用新题再考你。")

MODES = {"today": "今日任务（复习 + 本周技能）", "kc": "指定技能", "mistakes": "只复习错题"}

# 其他页面可以通过 drill_request 指定练习内容
if req := ss.pop("drill_request", None):
    ss["drill"] = drills.new_session(req["mode"], req.get("kc"), drills.daily_goal(progress))

if "drill" not in ss:
    with st.container(border=True):
        st.markdown("**选择练习方式**")
        mode = st.radio("练习方式", list(MODES), format_func=MODES.get, horizontal=True, label_visibility="collapsed")
        kc = None
        if mode == "kc":
            kc = st.selectbox("技能", list(KCS), format_func=lambda k: f"{KCS[k].name}（{KCS[k].en}）")
        due = len(drills.due_mistakes(progress))
        if mode == "mistakes":
            st.caption(f"今天到期的错题：{due} 道")
        if st.button("开始", type="primary", icon=":material/play_arrow:"):
            ss["drill"] = drills.new_session(mode, kc, drills.daily_goal(progress))
            st.rerun()
else:
    session = ss["drill"]
    ai_ready = ai.is_ready()

    top = st.columns([3, 1], vertical_alignment="center")
    with top[0]:
        done = session["count"]
        st.progress(min(done / session["goal"], 1.0),
                    text=f"本次已做 {done} 题 · 独立做对 {session['correct']} 题 · 目标 {session['goal']} 题")
    with top[1]:
        if st.button("结束本次练习", icon=":material/stop:", width="stretch"):
            ss.pop("drill")
            st.rerun()

    if done >= session["goal"] and not session.get("goal_celebrated"):
        session["goal_celebrated"] = True
        st.balloons()
    if done >= session["goal"]:
        with st.container(border=True):
            solo = session["correct"]
            st.success(f"本次目标完成！独立做对 {solo}/{done} 题。想继续刷就点“再来 10 题”，到期复习明天会自动安排。",
                       icon=":material/celebration:")
            practiced = sorted({x["kc"] for x in session["log"]})
            st.markdown("本次练过：" + " ".join(f"{KCS[k].name} {ui.tier_label(progress, k)}" for k in practiced))
            if st.button("再来 10 题", icon=":material/add:"):
                session["goal"] += 10
                st.rerun()

    cur = session.get("current")
    if cur is None or cur.get("finished_next"):
        item, reason, mistake, need_gen = drills.next_item(progress, session, ai_ready)
        if item is None and need_gen and ai_ready:
            made = ui.run_ai(f"正在为“{KCS[need_gen].name}”出新题…", drills.generate_items, progress, need_gen)
            if made:
                item, reason, mistake, need_gen = drills.next_item(progress, session, ai_ready)
        if item is None:
            if session["mode"] == "mistakes":
                st.info("没有到期的错题了。错题会按遗忘规律在之后几天再出现。", icon=":material/check_circle:")
            elif not ai_ready:
                st.info("这个范围的种子题已经做完了。连接 AI 后可以无限生成新题，也可以换一个技能继续。",
                        icon=":material/info:")
            else:
                st.warning("暂时没有可练的题，换一个技能试试。")
            if st.button("换一种练习方式"):
                ss.pop("drill")
                st.rerun()
            cur = None
        else:
            cur = {"item": item.model_dump(), "reason": reason, "mistake_id": mistake["id"] if mistake else None,
                   "start": time.time(), "first_submit": None, "wrong": 0, "hints": 0, "revealed": False,
                   "result": None, "finished": False, "n": session["count"]}
            session["current"] = cur

    if cur:
        item = Item.model_validate(cur["item"])
        mistake = next((m for m in progress["mistakes"] if m["id"] == cur["mistake_id"]), None)
        key = f"{item.id}_{cur['n']}"

        with st.container(border=True):
            with st.container(horizontal=True):
                ui.kc_badge(item.kc)
                st.badge(ui.format_label(item.format), color="gray")
                st.badge(cur["reason"], color="primary", icon=":material/schedule:")
                if item.source == "personal":
                    st.badge("你自己的句子", color="red", icon=":material/person:")
                elif item.source == "ai":
                    st.badge("AI 新题", color="gray", icon=":material/auto_awesome:")
            st.markdown(f"**{item.instruction}**")
            if item.content and item.format not in ("order",):
                with st.container(border=True):
                    st.markdown(ui.md_escape(item.content).replace("\n", "  \n"))

            finished = cur["finished"]
            response = None
            if item.format in ("mcq", "judge"):
                response = st.radio("选项", range(len(item.options)), index=None, key=f"ans_{key}",
                                    format_func=lambda i: item.options[i], label_visibility="collapsed",
                                    disabled=finished)
            elif item.format == "order":
                order = shuffled_order(item, key)
                labels = {i: f"{chr(65 + n)}. {item.sentences[i]}" for n, i in enumerate(order)}
                for i in order:
                    st.markdown(ui.md_escape(labels[i]))
                response = st.multiselect("按正确顺序依次选择句子", order, format_func=lambda i: labels[i][:2],
                                          key=f"ans_{key}", disabled=finished)
            else:
                default = item.content if item.format == "fix" else ""
                if f"ans_{key}" not in ss:
                    ss[f"ans_{key}"] = default
                response = st.text_area("你的答案", key=f"ans_{key}", height=120, disabled=finished)

            if not finished and cur["first_submit"] is None:
                st.segmented_control("提交前：你有多大把握？", ["有把握", "不太确定", "猜的"], key=f"conf_{key}")

            # ---------- 提交 ----------
            if not finished:
                cols = st.columns([1, 1, 1, 2])
                submit = cols[0].button("提交", type="primary", key=f"submit_{key}", icon=":material/send:",
                                        disabled=response is None or response == [] or response == "")
                # 每看一级提示前都要先再试一次（防止连点提示直接拿到答案）
                can_hint = cur["wrong"] >= cur["hints"] + 1 and cur["hints"] < len(item.hints)
                if cols[1].button(f"看提示 {cur['hints'] + 1}/{len(item.hints) or 3}", key=f"hint_{key}",
                                  disabled=not can_hint, help="先做一次再看提示；看完一级提示后要再试一次才能看下一级"):
                    cur["hints"] += 1
                    st.rerun()
                can_reveal = cur["wrong"] >= 2 or (cur["wrong"] >= 1 and cur["hints"] >= len(item.hints))
                if cols[2].button("看答案", key=f"reveal_{key}", disabled=not can_reveal,
                                  help="答错两次，或看完所有提示后才能看答案；看答案不算做对"):
                    cur["revealed"] = True
                    cur["finished"] = True
                    seconds = (cur["first_submit"] or time.time()) - cur["start"]
                    drills.finish_item(progress, session, item, 0.0, cur["hints"] + cur["wrong"], True,
                                       cur.get("confidence") or ss.get(f"conf_{key}"), seconds, mistake, str(response))
                    st.rerun()

                if submit:
                    if cur["first_submit"] is None:
                        cur["first_submit"] = time.time()
                        cur["confidence"] = ss.get(f"conf_{key}")
                    result = {"score": 0.0, "feedback": "", "hint": "", "good": "", "rule": ""}
                    if item.format in AUTO_GRADED or item.format == "fix":
                        score, fb = drills.grade_auto(item, response)
                        # 选择题的选项解析可能直接写出正确答案，答完这题之后才统一展示
                        result.update(score=score, feedback="" if item.format in ("mcq", "judge") else fb)
                    else:
                        score = -1.0
                    if score < 0:
                        if ai_ready:
                            g = ui.run_ai("老师正在看你的答案…", drills.grade_open, item, response, cur["wrong"] + 1,
                                          item.hints[:cur["hints"]])
                            if g:
                                result.update(score=min(max(g.score, 0.0), 1.0), feedback=g.issue, hint=g.hint,
                                              good=g.good, rule=g.rule, verdict=g.verdict)
                            else:
                                result = None
                        else:
                            result.update(score=0.0, offline=True,
                                          feedback="离线模式下只能和参考答案精确比对，你的答案和参考答案不同。")
                    if result is not None:
                        cur["result"] = result
                        if result["score"] >= 0.8:
                            cur["finished"] = True
                            drills.finish_item(progress, session, item, result["score"], cur["hints"] + cur["wrong"],
                                               False, cur.get("confidence"), cur["first_submit"] - cur["start"],
                                               mistake, str(response))
                        else:
                            cur["wrong"] += 1
                        st.rerun()

            # ---------- 反馈 ----------
            result = cur.get("result")
            if not finished and result and result["score"] < 0.8:
                msg = "部分正确，再改一改。" if result["score"] >= 0.4 else "还不对，再想想。"
                st.error(msg, icon=":material/close:")
                if cur.get("confidence") == "有把握" and cur["wrong"] == 1:
                    st.warning("你很有把握但答错了——这正是最值得弄清楚的地方：想想你用的是哪条规则。",
                               icon=":material/priority_high:")
                if result.get("good"):
                    st.markdown(f"👍 {result['good']}")
                if result.get("feedback"):
                    st.markdown(f"**问题：** {result['feedback']}")
                if result.get("hint"):
                    st.markdown(f"**提示：** {result['hint']}")
                if result.get("offline"):
                    st.caption("可以再试一次，或看提示/答案后自己对照。")
            for i in range(cur["hints"]):
                st.info(f"提示 {i + 1}：{item.hints[i]}", icon=":material/lightbulb:")

            if finished:
                if cur["revealed"]:
                    st.warning("这题看了答案，不算做对。稍后会用同类新题再考你，也已加入错题本。", icon=":material/visibility:")
                    st.text_input("看完答案后，用自己的话说说为什么这样才对（自我解释能帮你记住规则）",
                                  key=f"explain_{key}")
                else:
                    extra = "" if cur["wrong"] == 0 and cur["hints"] == 0 else "（有提示/重试，掌握度按“有帮助”计算）"
                    st.success(f"答对了！{extra}", icon=":material/check:")
                    if result and result.get("good"):
                        st.markdown(f"👍 {result['good']}")
                if item.format in ("mcq", "judge"):
                    st.markdown(f"**正确答案：** {ui.md_escape(item.options[item.answer])}")
                    if item.option_explanations:
                        with st.expander("每个选项为什么对 / 错", expanded=cur["revealed"] or cur["wrong"] > 0):
                            for i, (opt, why) in enumerate(zip(item.options, item.option_explanations)):
                                mark = "✅" if i == item.answer else "❌"
                                st.markdown(f"{mark} {ui.md_escape(opt)} — {why}")
                elif item.format == "order":
                    st.markdown("**正确顺序：**")
                    for n, s in enumerate(item.sentences, 1):
                        st.markdown(f"{n}. {ui.md_escape(s)}")
                elif item.accepted:
                    st.markdown("**参考答案**" + ("（你的答案不必一样）" if not cur["revealed"] else "") + "：")
                    for a in item.accepted[:3]:
                        st.markdown(f"- {ui.md_escape(a)}")
                if item.explanation:
                    st.markdown(f"**规则：** {item.explanation}")
                if result and result.get("rule") and result["rule"] not in item.explanation:
                    st.caption(result["rule"])
                st_kc = mastery.kc_state(progress, item.kc)
                st.caption(f"{KCS[item.kc].name}：{ui.tier_label(progress, item.kc)} · 预计掌握度 "
                           f"{mastery.mastery_pct(progress, item.kc)}% · 连续独立答对 {st_kc['streak']} 题")
                rule = drills.kc_rule_card(item.kc)
                if rule:
                    with st.popover("规则卡", icon=":material/menu_book:"):
                        st.markdown(rule)
                cols = st.columns([1, 1, 3])
                if cols[0].button("下一题", type="primary", key=f"next_{key}", icon=":material/arrow_forward:"):
                    cur["finished_next"] = True
                    st.rerun()
                if cols[1].button("这题有问题", key=f"flag_{key}", icon=":material/flag:",
                                  help="答案有误或题目不清楚？报告后这题不会再出现"):
                    drills.flag_item(progress, item.id)
                    st.toast("已记录，这道题不会再出现。谢谢！")
                    cur["finished_next"] = True
                    st.rerun()
