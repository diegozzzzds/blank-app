"""刷题引擎、掌握度、学习大纲校验、存储迁移的单元测试（不联网）。"""

from datetime import datetime, timedelta, timezone

import pytest

from essay_coach import drills, mastery, planner, store
from essay_coach.items import Item, seed_items
from essay_coach.skills import KCS, topo_order

T0 = datetime(2026, 10, 14, 8, tzinfo=timezone.utc)


@pytest.fixture
def progress(monkeypatch):
    monkeypatch.setattr(store, "save", lambda: None)
    p = store.new_progress()
    p["profile"] = {"level": "高中", "exam": "ielts", "minutes_per_day": 20}
    return p


def bank(kc):
    return [i for i in seed_items() if i.kc == kc]


def test_skill_graph_is_acyclic_and_ordered():
    order = topo_order()
    assert sorted(order) == sorted(KCS)
    for k in order:
        for p in KCS[k].prereqs:
            assert order.index(p) < order.index(k)


def test_learned_then_retained_then_transferred(progress):
    items = bank("sent_boundary")
    for n in range(8):
        st = mastery.record(progress, items[n % 4] if n < 4 else items[4 if n == 4 else n % 4], 1.0, 0, False,
                            True, 20, when=T0 + timedelta(minutes=n))
    # 只有 5 道不同的题：连续独立答对 ≥4 道不同的题、指数平均 ≥0.85 → 已学会
    assert st["tier"] == "learned"
    for d in (2, 5):
        st = mastery.record(progress, items[0], 1.0, 0, False, True, 20, when=T0 + timedelta(days=d))
    assert st["tier"] == "retained"
    mastery.mark_transfer(progress, "sent_boundary", True)
    assert progress["kc"]["sent_boundary"]["tier"] == "transferred"


def test_assisted_answers_do_not_build_streak(progress):
    item = bank("articles")[0]
    st = mastery.record(progress, item, 1.0, 2, False, None, 60, when=T0)
    assert st["streak"] == 0 and st["help_n"] == 1 and st["solo_n"] == 0
    st = mastery.record(progress, bank("articles")[1], 0.0, 0, True, None, 60, when=T0)
    assert st["ema"] < 0.3


def test_interval_capped_by_exam_date(progress):
    progress["profile"]["exam_date"] = (datetime.now(timezone.utc) + timedelta(days=10)).date().isoformat()
    card = None
    when = datetime.now(timezone.utc)
    for _ in range(6):
        card = mastery.review_card(progress, card, mastery.Rating.Easy, when)
        due = datetime.fromisoformat(card["due"])
        assert (due - when).days <= 2  # 10 天 × 20%
        when = due


def test_exam_date_in_past_does_not_crash(progress):
    progress["profile"]["exam_date"] = "2020-01-01"
    card = mastery.review_card(progress, None, mastery.Rating.Good, T0)
    assert card["due"]


def test_wrong_answer_requeues_skill_after_gap(progress):
    session = drills.new_session("kc", "articles")
    first, *_ = drills.next_item(progress, session, ai_ready=False)
    drills.finish_item(progress, session, first, 0.0, 0, True, None, 10, None, "x")
    assert session["requeue"] == [{"kc": "articles", "after": 1 + drills.REQUEUE_GAP}]
    assert len(progress["mistakes"]) == 1
    seen = [first.id]
    for _ in range(3):
        it, reason, *_ = drills.next_item(progress, session, ai_ready=False)
        assert it.id not in seen
        seen.append(it.id)
        drills.finish_item(progress, session, it, 1.0, 0, False, "有把握", 10, None, "")
    assert session["requeue"] == []


def test_confident_error_requeued_sooner(progress):
    session = drills.new_session("kc", "articles")
    it, *_ = drills.next_item(progress, session, ai_ready=False)
    drills.finish_item(progress, session, it, 0.0, 1, False, "有把握", 10, None, "x")
    assert session["requeue"][0]["after"] == session["count"] + 1


def test_mistake_retires_after_three_days(progress):
    item = bank("thesis")[0]
    m = drills.add_mistake(progress, "thesis", "bad thesis", "note", "drill", item=item)
    drills.review_mistake(progress, m, bank("thesis")[1], True, True, when=T0)
    drills.review_mistake(progress, m, bank("thesis")[2], True, True, when=T0 + timedelta(hours=1))  # 同一天不重复计
    assert len(m["reviews_ok"]) == 1
    drills.review_mistake(progress, m, bank("thesis")[1], True, True, when=T0 + timedelta(days=2))
    assert not m["retired"]
    drills.review_mistake(progress, m, bank("thesis")[3], True, True, when=T0 + timedelta(days=6))
    assert m["retired"]


def test_mistake_wrong_review_resets(progress):
    m = drills.add_mistake(progress, "thesis", "bad thesis", "note", "drill", item=bank("thesis")[0])
    drills.review_mistake(progress, m, bank("thesis")[1], True, True, when=T0)
    drills.review_mistake(progress, m, bank("thesis")[2], False, True, when=T0 + timedelta(days=1))
    assert m["reviews_ok"] == [] and not m["retired"]


def test_interleaving_avoids_three_in_a_row(progress):
    progress["plan"] = {"weeks": [{"kcs": ["articles", "sent_boundary"]}], "current_week": 0}
    session = drills.new_session("today")
    kcs = []
    for _ in range(8):
        it, *_ = drills.next_item(progress, session, ai_ready=False)
        kcs.append(it.kc)
        drills.finish_item(progress, session, it, 1.0, 0, False, None, 10, None, "")
    assert not any(kcs[i] == kcs[i + 1] == kcs[i + 2] for i in range(len(kcs) - 2))


def test_fix_grading_normalizes_but_rejects_unchanged():
    item = bank("sent_boundary")[-1]
    assert item.format == "fix"
    assert drills.grade_auto(item, "It is late; we should go home")[0] == 1.0
    assert drills.grade_auto(item, "  it is late,  so we should go home. ")[0] == 1.0
    assert drills.grade_auto(item, item.content)[0] == 0.0
    assert drills.grade_auto(item, "It is late, we should went home.")[0] == -1.0  # 需要 AI 判分


def test_order_partial_credit():
    item = next(i for i in seed_items() if i.format == "order")
    assert drills.grade_auto(item, [0, 1, 2])[0] == 1.0
    assert 0 < drills.grade_auto(item, [1, 2, 0])[0] < 1
    assert drills.grade_auto(item, [0, 1])[0] == 0.0


def test_streak_with_freeze(progress):
    today = datetime.now(timezone.utc).date()
    for d in (0, 1, 3, 4):  # 第 2 天没练：用补签
        progress["days"][(today - timedelta(days=d)).isoformat()] = {"items": 12, "solo_correct": 8}
    count, met = drills.streak(progress)
    assert met and count == 4


def test_ai_plan_is_repaired(progress):
    bad = planner.StudyPlan(overview="o", daily_routine="d", milestones=[], weeks=[
        planner.WeekPlan(title="w1", kcs=["critical_questions", "made_up", "articles"], goals=["g"], why="y",
                         lesson_focus="l", essay_task="e", checkpoint=False),
        planner.WeekPlan(title="w2", kcs=["prompt_analysis", "thesis", "topic_sentence", "support_evidence"],
                         goals=["g"], why="y", lesson_focus="l", essay_task="e", checkpoint=False),
    ])
    plan, notes = planner.validate_plan(progress, bad)
    seen: set[str] = set()
    for w in plan["weeks"]:
        assert len(w["kcs"]) <= planner.MAX_KCS_PER_WEEK
        for k in w["kcs"]:
            assert k in KCS
            assert all(p in seen or p in w["kcs"] for p in KCS[k].prereqs)
        seen.update(w["kcs"])
    assert "made_up" not in seen and "critical_questions" not in seen
    assert any("made_up" in n for n in notes)
    assert plan["weeks"][1]["checkpoint"]


def test_baseline_plan_respects_prerequisites(progress):
    plan = planner.baseline_plan(progress)
    seen: set[str] = set()
    for w in plan["weeks"]:
        for k in w["kcs"]:
            assert all(p in seen or p in w["kcs"] for p in KCS[k].prereqs)
        seen.update(w["kcs"])


def test_migrate_keeps_known_keys_only():
    data = {"kc": {"articles": {"tier": "learning"}}, "attempts": [], "evil": "x", "version": 1}
    p = store._migrate(data)
    assert "evil" not in p and p["version"] == store.SCHEMA_VERSION and p["kc"]["articles"]["tier"] == "learning"


def test_items_problem_checks():
    good = bank("articles")[0]
    assert good.problems() == []
    bad = Item(**{**good.model_dump(), "answer": 9})
    assert bad.problems()
    personal = Item(id="me-x", kc="articles", format="fix", difficulty=3, instruction="i", content="I have a apple.",
                    source="personal")
    assert personal.problems() == [] and drills.needs_ai(personal)
