"""掌握度与复习安排。

- 能力估计：每个技能点一个 Elo 能力值 θ，每道题一个难度 b（Pelánek 2016 的自适应练习做法），
  P(答对) = g + (1 - g)·σ(θ - b)，选择题的 g = 1/选项数（猜对概率）。
- 只用“独立完成”的表现计算掌握度：用了提示的作答按比例打折，看了答案按 0 计（Bastani et al. 2025：
  有帮助时的正确率会制造“学会了”的错觉）。
- 三级掌握（参考 Bloom 掌握学习 + 连续正确标准）：
    已学会 learned：独立正确率的指数平均 ≥ 0.85，且连续独立答对 ≥ 4 道不同的题
    已巩固 retained：学会后，在间隔 ≥ 1 天的两次复习里首题都独立答对
    已迁移 transferred：在一篇独立完成的作文里用对了这个技能（作文批改给出证据）
- 复习安排：每个技能点一张 FSRS 卡片（py-fsrs，desired_retention 0.9），每天只用当天该技能的第一题打分，
  间隔不超过离考试天数的 20%（Cepeda et al. 2008：间隔应与保持时长成比例）。
"""

import math
from datetime import datetime, timedelta, timezone

from fsrs import Card, Rating, Scheduler

from .skills import KCS

TIERS = {
    "new": ("未开始", "gray"),
    "learning": ("练习中", "orange"),
    "learned": ("已学会", "blue"),
    "retained": ("已巩固", "violet"),
    "transferred": ("已迁移", "green"),
}
TIER_RANK = {k: i for i, k in enumerate(TIERS)}

EMA_ALPHA = 0.3
LEARNED_EMA = 0.85
LEARNED_STREAK = 4
RETAINED_REVIEWS = 2


def _sigmoid(x: float) -> float:
    return 1 / (1 + math.exp(-x))


def seed_difficulty(level: int) -> float:
    """题目标注难度 1–5 → 初始 Elo 难度。"""
    return (level - 3) * 0.8


def kc_state(progress: dict, kc: str) -> dict:
    state = progress["kc"].setdefault(kc, {})
    for key, default in (("theta", 0.0), ("n", 0), ("ema", 0.0), ("streak", 0), ("tier", "new"),
                         ("learned_at", None), ("reviews_ok", []), ("card", None), ("last_day", None),
                         ("solo_n", 0), ("solo_ok", 0), ("help_n", 0), ("help_ok", 0), ("streak_items", [])):
        state.setdefault(key, default)
    return state


def item_difficulty(progress: dict, item) -> float:
    rec = progress["items"].get(item.id)
    return rec["b"] if rec else seed_difficulty(item.difficulty)


def guess_rate(item) -> float:
    if item.format in ("mcq", "judge") and item.options:
        return 1 / len(item.options)
    return 0.0


def p_correct(progress: dict, item) -> float:
    theta = kc_state(progress, item.kc)["theta"]
    g = guess_rate(item)
    return g + (1 - g) * _sigmoid(theta - item_difficulty(progress, item))


def mastery_pct(progress: dict, kc: str) -> int:
    """在一道中等难度（b=0）开放题上的预计正确率，用于展示。"""
    st = progress["kc"].get(kc)
    if not st or not st.get("n"):
        return 0
    return round(_sigmoid(st["theta"]) * 100)


def outcome_value(score: float, hints: int, revealed: bool) -> float:
    if revealed:
        return 0.0
    return max(0.0, score * (1 - 0.25 * hints))


def _rating(score: float, hints: int, revealed: bool, confident: bool | None, fast: bool) -> Rating:
    if revealed or score < 0.5:
        return Rating.Again
    if hints or score < 0.8:
        return Rating.Hard
    if confident and fast:
        return Rating.Easy
    return Rating.Good


def scheduler(progress: dict) -> Scheduler:
    profile = progress.get("profile") or {}
    retention = 0.85 if profile.get("level") in ("初中",) else 0.9
    max_days = 60
    exam = profile.get("exam_date")
    if exam:
        try:
            days_left = (datetime.fromisoformat(exam).date() - datetime.now(timezone.utc).date()).days
            max_days = max(1, min(max_days, int(days_left * 0.2)))
        except ValueError:
            pass
    return Scheduler(desired_retention=retention, learning_steps=(), relearning_steps=(),
                     maximum_interval=max_days, enable_fuzzing=False)


def review_card(progress: dict, card: dict | None, rating: Rating, when: datetime) -> dict:
    c = Card.from_dict(card) if card else Card()
    c, _ = scheduler(progress).review_card(c, rating, when)
    return c.to_dict()


def card_due(card: dict | None, when: datetime) -> bool:
    if not card:
        return False
    return datetime.fromisoformat(card["due"]) <= when


def record(progress: dict, item, score: float, hints: int, revealed: bool,
           confident: bool | None = None, seconds: float | None = None, when: datetime | None = None) -> dict:
    """记录一次作答，更新能力值、题目难度、掌握等级和复习卡片。返回该技能点的新状态。"""
    when = when or datetime.now(timezone.utc)
    day = when.date().isoformat()
    st = kc_state(progress, item.kc)
    o = outcome_value(score, hints, revealed)
    solo = hints == 0 and not revealed
    p = p_correct(progress, item)

    # Elo：不确定性随作答次数下降
    k_student = 1 / (1 + 0.05 * st["n"])
    rec = progress["items"].setdefault(item.id, {"b": seed_difficulty(item.difficulty), "n": 0})
    k_item = 1 / (1 + 0.05 * rec["n"])
    st["theta"] += k_student * (o - p)
    rec["b"] -= k_item * (o - p) * 0.5
    st["n"] += 1
    rec["n"] += 1

    correct = score >= 0.8
    if solo:
        st["solo_n"] += 1
        st["solo_ok"] += int(correct)
    else:
        st["help_n"] += 1
        st["help_ok"] += int(correct and not revealed)

    st["ema"] = (1 - EMA_ALPHA) * st["ema"] + EMA_ALPHA * o
    if solo and correct:
        if item.id not in st["streak_items"]:
            st["streak_items"].append(item.id)
        st["streak"] = len(st["streak_items"])
    else:
        st["streak_items"] = []
        st["streak"] = 0

    # 每天只用第一题更新复习卡片
    first_today = st["last_day"] != day
    if first_today:
        fast = seconds is not None and seconds < 45
        st["card"] = review_card(progress, st["card"], _rating(score, hints, revealed, confident, fast), when)
        if st["learned_at"] and day > st["learned_at"][:10] and solo and correct:
            if not st["reviews_ok"] or day > st["reviews_ok"][-1]:
                st["reviews_ok"].append(day)
        st["last_day"] = day

    _update_tier(st, when)
    return st


def _update_tier(st: dict, when: datetime) -> None:
    tier = st["tier"]
    if st["n"] and tier == "new":
        tier = "learning"
    if TIER_RANK[tier] < TIER_RANK["learned"] and st["ema"] >= LEARNED_EMA and st["streak"] >= LEARNED_STREAK:
        tier = "learned"
        st["learned_at"] = when.isoformat()
        st["reviews_ok"] = []
    if tier == "learned" and len(st["reviews_ok"]) >= RETAINED_REVIEWS:
        tier = "retained"
    # 学会后又明显退步：退回练习中，重新达标
    if TIER_RANK[tier] >= TIER_RANK["learned"] and st["ema"] < 0.5 and st["streak"] == 0:
        tier = "learning"
        st["learned_at"] = None
        st["reviews_ok"] = []
    st["tier"] = tier


def mark_transfer(progress: dict, kc: str, demonstrated: bool) -> None:
    """作文批改给出的迁移证据：已巩固的技能在独立作文中用对 → 已迁移；用错 → 降回已学会并安排复习。"""
    if kc not in KCS:
        return
    st = kc_state(progress, kc)
    if demonstrated and st["tier"] == "retained":
        st["tier"] = "transferred"
    elif not demonstrated and st["tier"] in ("retained", "transferred"):
        st["tier"] = "learned"
        st["reviews_ok"] = []
        st["card"] = review_card(progress, st["card"], Rating.Again, datetime.now(timezone.utc))


def is_unlocked(progress: dict, kc: str) -> bool:
    """前置技能都至少“练习中”且掌握度过半，或已学会。"""
    for p in KCS[kc].prereqs:
        st = progress["kc"].get(p)
        if not st:
            return False
        if TIER_RANK[st["tier"]] < TIER_RANK["learned"] and st["ema"] < 0.6:
            return False
    return True


def due_kcs(progress: dict, when: datetime | None = None) -> list[str]:
    when = when or datetime.now(timezone.utc)
    return [k for k, st in progress["kc"].items()
            if k in KCS and st.get("tier") != "new" and card_due(st.get("card"), when)]


def next_review(progress: dict, kc: str) -> datetime | None:
    card = (progress["kc"].get(kc) or {}).get("card")
    return datetime.fromisoformat(card["due"]) if card else None


def solo_vs_help(progress: dict) -> tuple[tuple[int, int], tuple[int, int]]:
    solo = sum(s.get("solo_ok", 0) for s in progress["kc"].values()), sum(s.get("solo_n", 0) for s in progress["kc"].values())
    helped = sum(s.get("help_ok", 0) for s in progress["kc"].values()), sum(s.get("help_n", 0) for s in progress["kc"].values())
    return solo, helped


def retention_now(progress: dict, kc: str) -> float | None:
    card = (progress["kc"].get(kc) or {}).get("card")
    if not card:
        return None
    return scheduler(progress).get_card_retrievability(Card.from_dict(card), datetime.now(timezone.utc))


def ensure_aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def days_until(dt: datetime) -> float:
    return (ensure_aware(dt) - datetime.now(timezone.utc)) / timedelta(days=1)
