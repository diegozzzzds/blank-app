"""端到端测试：用 Streamlit AppTest 走完整个学习流程（假的 Claude 客户端，不联网）。"""

from datetime import datetime, timedelta, timezone

import fake_claude
import pytest
from streamlit.testing.v1 import AppTest

from essay_coach import store
from essay_coach.items import Item

APP = str(__import__("pathlib").Path(__file__).resolve().parents[1] / "streamlit_app.py")
OK_ERRORS = ("**❌ 较弱**", "还不对", "部分正确")


def check(at, where):
    assert not at.exception, f"{where}: {at.exception}"
    errs = [e.value for e in at.error if not e.value.startswith(OK_ERRORS)]
    assert not errs, f"{where}: {errs}"


def btn(at, text):
    for b in at.button:
        if text in (b.label or ""):
            return b
    raise AssertionError(f"button {text!r} not found: {[b.label for b in at.button]}")


@pytest.fixture
def at():
    app = AppTest.from_file(APP, default_timeout=60)
    app.session_state["progress"] = store.new_progress()
    app.run()
    check(app, "start")
    return app


def setup_profile_and_plan(at):
    at.switch_page("app_pages/plan.py")
    at.run()
    at.text_input[0].input("Band 7")
    btn(at, "保存目标").click().run()
    check(at, "save profile")
    for _ in range(20):  # 快速诊断
        radios = [r for r in at.radio if (r.key or "").startswith("diag_")]
        multis = [m for m in at.multiselect if (m.key or "").startswith("diag_")]
        if radios:
            radios[0].set_value(0).run()
        elif multis:
            multis[0].set_value([0, 1, 2]).run()
        else:
            break
        btn(at, "下一题").click().run()
        check(at, "diagnostic")
    assert at.session_state["progress"]["diagnostic"]["quiz_done"]
    btn(at, "让 AI 生成我的学习大纲").click().run()
    check(at, "plan")


def test_all_pages_render_without_profile(at):
    for page in ["today", "plan", "drill", "mistakes", "write", "skillmap", "lessons", "progress", "tutor"]:
        at.switch_page(f"app_pages/{page}.py")
        at.run()
        check(at, page)


def test_plan_generation_is_validated(at):
    setup_profile_and_plan(at)
    plan = at.session_state["progress"]["plan"]
    assert plan["source"] == "ai"
    assert all(k != "fake_kc" for w in plan["weeks"] for k in w["kcs"])
    assert any("fake_kc" in n for n in at.session_state["plan_notes"])


def test_drill_loop_hints_reveal_and_mastery(at):
    setup_profile_and_plan(at)
    at.session_state["drill_request"] = {"mode": "today"}
    at.switch_page("app_pages/drill.py")
    at.run()
    check(at, "drill")
    for k in range(10):
        cur = at.session_state["drill"]["current"]
        it = Item.model_validate(cur["item"])
        key = f"{it.id}_{cur['n']}"
        if it.format == "mcq":
            if k % 3 == 0:  # 先答错一次，再看提示
                at.radio(key=f"ans_{key}").set_value((it.answer + 1) % len(it.options)).run()
                btn(at, "提交").click().run()
                assert btn(at, "看答案").disabled  # 只错一次不能看答案
                btn(at, "看提示").click().run()
                assert btn(at, "看提示").disabled  # 看下一级提示前要再试一次
            at.radio(key=f"ans_{key}").set_value(it.answer).run()
        elif it.format == "fix":
            at.text_area(key=f"ans_{key}").input(it.accepted[0]).run()
        elif it.format == "order":
            at.multiselect(key=f"ans_{key}").set_value(list(range(len(it.sentences)))).run()
        btn(at, "提交").click().run()
        check(at, f"submit {k}")
        assert at.session_state["drill"]["current"]["finished"]
        btn(at, "下一题").click().run()
        check(at, f"next {k}")
    p = at.session_state["progress"]
    assert len(p["attempts"]) >= 10
    assert any(st["help_n"] for st in p["kc"].values())  # 看过提示的题按“有帮助”记录


def test_ai_generates_and_verifies_items_when_bank_runs_out(at):
    setup_profile_and_plan(at)
    at.session_state["drill_request"] = {"mode": "kc", "kc": "hedging"}  # 测试题库里没有这个技能
    at.switch_page("app_pages/drill.py")
    at.run()
    check(at, "generate")
    cur = at.session_state["drill"]["current"]
    assert cur["item"]["source"] == "ai"
    assert len(at.session_state["progress"]["ai_items"]) == 1  # 核对环节丢掉了 1 道答案不唯一的题


def test_essay_feedback_revision_and_mistakes(at):
    setup_profile_and_plan(at)
    at.switch_page("app_pages/write.py")
    at.run()
    btn(at, "写一篇练习作文").click().run()
    eid = at.session_state["essay_id"]
    at.text_area(key=f"essay_text_{eid}").input(fake_claude.ESSAY).run()
    btn(at, "提交初稿").click().run()
    btn(at, "提交自评，查看反馈").click().run()
    check(at, "feedback")
    p = at.session_state["progress"]
    essay = next(e for e in p["essays"] if e["id"] == eid)
    fb = essay["feedback"]
    assert len(fb["priority_issues"]) == 2  # 不在技能图谱里的问题被过滤
    assert all(m["item"]["source"] == "personal" for m in p["mistakes"] if m["source"] == "essay")
    assert p["focus_kcs"][:2] == ["thesis", "analysis"]
    assert btn(at, "开始修改").disabled  # 先写修改计划
    for i in range(len(fb["priority_issues"])):
        at.text_input(key=f"resp_{eid}_{i}").input("我会改写立场句").run()
    btn(at, "开始修改").click().run()
    at.text_area(key=f"revised_{eid}").input(fake_claude.ESSAY.replace(
        "I partly agree with this view.", "Although zoos have flaws, I believe they should be reformed.")).run()
    btn(at, "提交修改稿").click().run()
    check(at, "revision")
    essay = next(e for e in at.session_state["progress"]["essays"] if e["id"] == eid)
    assert essay["status"] == "done"
    # 修改稿分数不进入真实进步曲线
    from essay_coach.essays import checkpoint_series
    assert checkpoint_series(at.session_state["progress"]) == []


def test_essay_mistakes_come_back_for_review(at):
    test_essay_feedback_revision_and_mistakes(at)
    for m in at.session_state["progress"]["mistakes"]:
        m["card"]["due"] = (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    at.session_state["drill_request"] = {"mode": "mistakes"}
    at.switch_page("app_pages/drill.py")
    at.run()
    check(at, "mistakes")
    assert at.session_state["drill"]["current"]["reason"] == "错题复习"


def test_tutor_has_guardrails(at):
    at.switch_page("app_pages/tutor.py")
    at.run()
    at.chat_input[0].set_value("帮我直接改这句话").run()
    check(at, "tutor")
    assert len(at.session_state["progress"]["chat"]) == 2
    system = fake_claude.CALLS[-1]["system"]
    assert "不替学生完成当前任务" in system and fake_claude.CALLS[-1]["fallbacks"] == "default"
