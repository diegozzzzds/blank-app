"""刷题引擎：选题、判分、提示阶梯、错题本、AI 出新题。

选题顺序（每次只出一题）：
  1. 本次练习中做错的技能：间隔至少 2 题后用“同类新题”再测（最多再测 2 次）
  2. 到期的错题（successive relearning：不同日期独立答对 3 次才移出错题本）
  3. 到期的技能复习（FSRS）
  4. 学习大纲本周的技能
  5. 其他已解锁、掌握度最低的技能
  同一技能不连续出现 3 次以上（交错练习）；题目难度对准预计正确率约 75%（Wilson et al. 2019 的“85% 规则”，
  对写作这类复杂技能取得更低一些）。

作答规则（“先尝试，再提示，最后才看答案”）：
  第一次提交前不能看提示；答错后可以逐级看 3 个提示；答错两次或看完提示后才能看答案；
  看答案算作没答对，会进入错题本，并在本次练习稍后用同类新题再测。
"""

import hashlib
import re
from datetime import datetime, timedelta, timezone

from pydantic import BaseModel, Field

from . import ai, mastery, store
from .items import Item, rule_cards, seed_items
from .skills import AUTO_GRADED, FORMATS, KCS

TARGET_P = 0.75
REQUEUE_GAP = 2
MAX_REQUEUE = 2
MISTAKE_RETIRE_REVIEWS = 3


# ---------------- 题库 ----------------

def all_items(progress: dict) -> list[Item]:
    flagged = set(progress.get("flagged_items", []))
    items = [i for i in seed_items() if i.id not in flagged]
    for raw in progress["ai_items"]:
        if raw["id"] in flagged:
            continue
        try:
            it = Item.model_validate(raw)
        except ValueError:
            continue
        if not it.problems():
            items.append(it)
    return items


def find_item(progress: dict, item_id: str) -> Item | None:
    for it in all_items(progress):
        if it.id == item_id:
            return it
    for m in progress["mistakes"]:
        if m.get("item") and m["item"]["id"] == item_id:
            return Item.model_validate(m["item"])
    return None


def needs_ai(item: Item) -> bool:
    """开放题需要 AI 判分；改错题有参考答案时可以先精确比对。"""
    if item.format == "fix":
        return not item.accepted
    return item.format not in AUTO_GRADED


def _recent_item_ids(progress: dict, n: int = 60) -> set[str]:
    return {a["item"] for a in progress["attempts"][-n:]}


def pick_item(progress: dict, kc: str, exclude: set[str], ai_ready: bool) -> Item | None:
    """为技能 kc 选一道题：没做过的优先，难度最接近目标正确率。"""
    level = (progress.get("profile") or {}).get("level")
    target = 0.8 if level == "初中" else TARGET_P
    candidates = [i for i in all_items(progress) if i.kc == kc and i.id not in exclude]
    if not ai_ready:
        candidates = [i for i in candidates if not needs_ai(i)]
    if not candidates:
        return None
    recent = _recent_item_ids(progress)
    fresh = [i for i in candidates if i.id not in recent and i.id not in progress["items"]]
    pool = fresh or [i for i in candidates if i.id not in recent] or candidates
    return min(pool, key=lambda i: (abs(mastery.p_correct(progress, i) - target), i.id))


# ---------------- 选题 ----------------

def new_session(mode: str, kc: str | None = None, goal: int = 15) -> dict:
    return {"mode": mode, "kc": kc, "goal": goal, "count": 0, "correct": 0, "requeue": [],
            "recent_kcs": [], "seen": [], "current": None, "log": [], "gen_tried": []}


def current_week_kcs(progress: dict) -> list[str]:
    from .planner import current_week

    week = current_week(progress)
    return [k for k in week["kcs"] if k in KCS] if week else []


def due_mistakes(progress: dict, when: datetime | None = None, ai_ready: bool = True) -> list[dict]:
    """到期的错题。离线时只算有题可出的（自己的句子需要 AI 判分，同类题至少要有一道能自动判分）。"""
    when = when or datetime.now(timezone.utc)
    due = [m for m in progress["mistakes"] if not m.get("retired") and mastery.card_due(m.get("card"), when, progress)]
    if ai_ready:
        return due
    return [m for m in due if pick_item(progress, m["kc"], set(), False) is not None]


def weakest_unlocked(progress: dict, exclude: list[str]) -> list[str]:
    ks = [k for k in KCS if mastery.is_unlocked(progress, k) and k not in exclude]
    return sorted(ks, key=lambda k: (mastery.TIER_RANK[mastery.kc_state(progress, k)["tier"]],
                                     mastery.mastery_pct(progress, k), -KCS[k].prior))


def _too_repetitive(session: dict, kc: str) -> bool:
    return session["recent_kcs"][-2:] == [kc, kc]


def candidate_kcs(progress: dict, session: dict, ai_ready: bool = True) -> list[tuple[str, str, dict | None]]:
    """按优先级返回 (技能, 原因, 关联错题)。"""
    out: list[tuple[str, str, dict | None]] = []
    for r in session["requeue"]:
        if r["after"] <= session["count"]:
            out.append((r["kc"], "再测一次刚才做错的技能", r.get("mistake")))
    if session["mode"] == "kc" and session["kc"]:
        out.append((session["kc"], "指定练习", None))
        return out
    mistakes = due_mistakes(progress, ai_ready=ai_ready)
    for m in mistakes:
        out.append((m["kc"], "错题复习", m))
    if session["mode"] == "mistakes":
        return out
    for k in mastery.due_kcs(progress):
        out.append((k, "到期复习", None))
    for k in progress.get("focus_kcs", []):  # 最近一篇作文暴露的弱项
        if k in KCS:
            out.append((k, "上篇作文的弱项", None))
    for k in current_week_kcs(progress):
        out.append((k, "本周学习目标", None))
    # 补充最薄弱的可学技能；离线时跳过已经没有可做题目的技能，避免练习提前结束
    seen = set(session["seen"])
    added = 0
    for k in weakest_unlocked(progress, [c[0] for c in out]):
        if added >= 6:
            break
        if ai_ready or pick_item(progress, k, seen, False) is not None:
            out.append((k, "薄弱技能", None))
            added += 1
    return out


def next_item(progress: dict, session: dict, ai_ready: bool) -> tuple[Item | None, str, dict | None, str | None]:
    """返回 (题目, 原因, 关联错题, 需要 AI 生成题目的技能)。"""
    seen = set(session["seen"])
    need_gen = None
    cands = candidate_kcs(progress, session, ai_ready)
    # 刚做错、还在等待再测的技能先不出（保证中间隔开几题）；同一技能不连续出现 3 次（交错练习）
    waiting = {r["kc"] for r in session["requeue"] if r["after"] > session["count"]}

    def rank(c):
        return (c[0] in waiting and not c[1].startswith("再测"), _too_repetitive(session, c[0]))

    ordered = sorted(cands, key=rank)
    for kc, reason, mistake in ordered:
        flagged = set(progress.get("flagged_items", []))
        if mistake and mistake.get("item") and not mistake.get("personal_done") and mistake["item"]["id"] not in flagged:
            it = Item.model_validate(mistake["item"])
            if it.id not in seen and (ai_ready or not needs_ai(it)):
                return it, reason, mistake, None
        it = pick_item(progress, kc, seen, ai_ready)
        if it:
            return it, reason, mistake, None
        if need_gen is None and ai_ready and kc not in session.get("gen_tried", []):
            need_gen = kc
    return None, "", None, need_gen


# ---------------- 判分 ----------------

_QUOTES = str.maketrans({"’": "'", "‘": "'", "“": '"', "”": '"', " ": " "})


def _clean(text: str) -> str:
    """只统一引号和空白，保留大小写和标点前的空格。"""
    return re.sub(r"\s+", " ", text.translate(_QUOTES)).strip()


def normalize(text: str) -> str:
    """宽松比较：再忽略大小写、标点前的空格和句末句号。只用来判断“是否需要交给 AI”。"""
    t = re.sub(r"\s+([,.;:!?])", r"\1", _clean(text))
    return t.rstrip(".").lower()


class DrillGrade(BaseModel):
    score: float = Field(description="0–1：1 = 完全达到要求，0.5 = 部分达到，0 = 没有达到")
    verdict: str = Field(description="一句话判断（中文）")
    good: str = Field(description="答案中做对的地方；没有则写空字符串")
    issue: str = Field(description="还有什么问题、为什么；不要写出改正后的句子")
    hint: str = Field(description="下一次尝试的提示：指出方向，不给答案")
    rule: str = Field(description="相关规则，一句话")


def grade_auto(item: Item, response) -> tuple[float, str]:
    if item.format in ("mcq", "judge"):
        ok = response == item.answer
        return (1.0 if ok else 0.0), (item.option_explanations[response] if item.option_explanations
                                      and response is not None and 0 <= response < len(item.options) else "")
    if item.format == "order":
        # response：学生给出的句子顺序（原始下标）。相邻顺序对的比例作为部分得分
        if not response or len(response) != len(item.sentences):
            return 0.0, "请把所有句子都排进去。"
        if list(response) == list(range(len(item.sentences))):
            return 1.0, ""
        pairs = sum(1 for a, b in zip(response, response[1:]) if b == a + 1)
        return round(pairs / (len(item.sentences) - 1) * 0.7, 2), ""
    if item.format == "fix":
        answer = _clean(response or "")
        if answer == _clean(item.content):
            return 0.0, "你还没有修改原句。"
        # 和参考答案完全一致（只允许句末句号不同）才直接判对
        if any(answer.rstrip(".") == _clean(a).rstrip(".") for a in item.accepted):
            return 1.0, ""
        if any(normalize(answer) == normalize(a) for a in item.accepted):
            return -1.0, "和参考答案只差大小写或标点前的空格，请检查一下。"
        return -1.0, ""  # 需要 AI 判断
    return -1.0, ""


def grade_open(item: Item, response: str, attempt_no: int, hints_used: list[str]) -> DrillGrade:
    from . import prompts

    system, user = prompts.drill_grade_request(item, response, attempt_no, hints_used)
    return ai.structured(system, user, DrillGrade, max_tokens=6000, effort="low")


# ---------------- AI 出题 ----------------

class ItemDraft(BaseModel):
    format: str
    difficulty: int
    instruction: str
    content: str
    options: list[str]
    answer: int
    option_explanations: list[str]
    sentences: list[str]
    accepted: list[str]
    criteria: str
    hints: list[str]
    explanation: str


class ItemBatch(BaseModel):
    items: list[ItemDraft]


class ItemCheck(BaseModel):
    index: int = Field(description="题目序号（从 1 开始）")
    ok: bool = Field(description="答案唯一正确、英文无误、提示不泄露答案时为 true")
    problem: str = Field(description="有问题时说明问题；没有则为空字符串")


class ItemCheckBatch(BaseModel):
    results: list[ItemCheck]


def generate_items(progress: dict, kc: str, n: int = 4) -> list[Item]:
    from . import prompts

    st = mastery.kc_state(progress, kc)
    # 目标难度：让预计正确率接近 TARGET_P（θ - b ≈ 1.1）
    target_b = st["theta"] - 1.1
    difficulty = int(min(5, max(1, round(target_b / 0.8 + 3))))
    examples = [i for i in seed_items() if i.kc == kc][:3]
    seen_contents = [i.content or i.instruction for i in all_items(progress) if i.kc == kc][-15:]
    personal = [m["text"] for m in progress["mistakes"]
                if m["kc"] == kc and m.get("text") and m.get("format", "fix") not in AUTO_GRADED][-5:]
    system, user = prompts.item_generation_request(kc, n, difficulty, examples, seen_contents, personal,
                                                   (progress.get("profile") or {}).get("level", "高中"))
    batch = ai.structured(system, user, ItemBatch, max_tokens=16000, effort="medium")
    # 第二次调用逐题核对答案（Pardos & Bhandari 2024：未经核对的 AI 提示有相当比例不合格）
    # 核对失败或漏掉的题一律不用（宁可少出题，也不让没核对过的题给学生做）
    vsys, vuser = prompts.item_check_request(kc, [d.model_dump() for d in batch.items])
    checks = ai.structured(vsys, vuser, ItemCheckBatch, max_tokens=6000, effort="low")
    passed = {c.index for c in checks.results if c.ok}
    made = []
    for n, d in enumerate(batch.items, 1):
        if n not in passed:
            continue
        digest = hashlib.sha1(f"{kc}|{d.content}|{d.instruction}|{d.options}".encode()).hexdigest()[:10]
        try:
            it = Item(id=f"ai-{kc}-{digest}", kc=kc, source="ai", **d.model_dump())
        except ValueError:
            continue
        if it.format in KCS[kc].formats and not it.problems() and len(it.hints) >= 1:
            made.append(it)
    existing = {x["id"] for x in progress["ai_items"]}
    progress["ai_items"].extend(i.model_dump() for i in made if i.id not in existing)
    store.save()
    return made


# ---------------- 记录作答 ----------------

def _day_stats(progress: dict) -> dict:
    return progress["days"].setdefault(store.today(), {"items": 0, "solo_correct": 0})


def add_mistake(progress: dict, kc: str, text: str, note: str, source: str,
                item: Item | None = None, personal_item: dict | None = None) -> dict:
    when = store.now()
    card = mastery.review_card(progress, None, mastery.Rating.Again, when)
    card["due"] = (when + timedelta(days=1)).isoformat()
    m = {
        "id": hashlib.sha1(f"{kc}|{text}|{when.isoformat()}".encode()).hexdigest()[:12],
        "kc": kc, "text": text, "note": note, "source": source,
        "item_id": item.id if item else (personal_item or {}).get("id"),
        "item": personal_item, "personal_done": False,
        "format": item.format if item else (personal_item or {}).get("format", "fix"),
        "created": when.isoformat(), "card": card, "reviews_ok": [], "retired": False,
    }
    progress["mistakes"].append(m)
    return m


def review_mistake(progress: dict, mistake: dict, item: Item, correct: bool, solo: bool,
                   when: datetime | None = None) -> None:
    when = when or store.now()
    day = store.study_day(when).isoformat()
    if mistake.get("item") and item.id == mistake["item"]["id"] and correct:
        mistake["personal_done"] = True
    rating = mastery.Rating.Good if (correct and solo) else mastery.Rating.Again
    mistake["card"] = mastery.review_card(progress, mistake["card"], rating, when)
    if correct and solo and (not mistake["reviews_ok"] or mistake["reviews_ok"][-1] < day):
        mistake["reviews_ok"].append(day)
    if not (correct and solo):
        mistake["reviews_ok"] = []
    if len(mistake["reviews_ok"]) >= MISTAKE_RETIRE_REVIEWS:
        mistake["retired"] = True


def answer_text(item: Item, response) -> str:
    """把学生的作答转成可读文字（写进错题本）。"""
    if item.format in ("mcq", "judge"):
        chosen = item.options[response] if isinstance(response, int) and 0 <= response < len(item.options) else "（未作答）"
        return f"{item.content}\n我的选择：{chosen}".strip()
    if item.format == "order":
        order = [item.sentences[i] for i in (response or []) if 0 <= i < len(item.sentences)]
        return "我的顺序：" + " / ".join(order)
    return str(response or "")


def finish_item(progress: dict, session: dict, item: Item, score: float, hints: int, revealed: bool,
                confidence: str | None, seconds: float, mistake: dict | None, answer: str, wrong: int = 0) -> dict:
    """一道题结束（答对或看了答案）时调用：更新掌握度、错题本、本次练习队列。

    hints：看了几级提示；wrong：答错了几次后才做对。两者都算“有帮助”。
    """
    correct = score >= 0.8 and not revealed
    assisted = hints + wrong
    solo = assisted == 0 and not revealed
    missed = not correct or wrong > 0  # 中途答错过，即使后来改对了，也要再测
    confident = {"有把握": True, "不太确定": False, "猜的": False}.get(confidence or "")
    kc_st = mastery.record(progress, item, score, assisted, revealed, confident, seconds)
    progress["attempts"].append({
        "t": store.now().isoformat(), "item": item.id, "kc": item.kc, "format": item.format,
        "score": round(score, 2), "hints": hints, "wrong": wrong, "revealed": revealed, "confidence": confidence,
        "seconds": round(seconds, 1), "mode": session["mode"],
    })
    day = _day_stats(progress)
    day["items"] += 1
    day["done"] = day.get("done", 0) + int(not revealed)  # 连续学习天数只算没看答案的题
    day["solo_correct"] += int(correct and solo)

    if mistake:
        review_mistake(progress, mistake, item, correct, solo)
    elif not correct or hints >= 2 or (wrong and confident):
        add_mistake(progress, item.kc, answer, item.explanation[:200], "drill", item=item)

    session["count"] += 1
    session["correct"] += int(correct and solo)
    session["seen"].append(item.id)
    session["recent_kcs"].append(item.kc)
    session["requeue"] = [r for r in session["requeue"] if not (r["kc"] == item.kc and r["after"] <= session["count"] - 1)]
    if missed:
        times = sum(1 for x in session["log"] if x["kc"] == item.kc and x.get("missed", not x["correct"]))
        if times < MAX_REQUEUE:
            # 有把握却答错（高信心错误）更早再测（Metcalfe 2017：这类错误最容易被纠正）
            gap = 1 if confident else REQUEUE_GAP
            session["requeue"].append({"kc": item.kc, "after": session["count"] + gap})
    session["log"].append({"kc": item.kc, "item": item.id, "correct": correct, "solo": solo, "score": score,
                           "missed": missed})
    store.save()
    return kc_st


def flag_item(progress: dict, item_id: str) -> None:
    progress.setdefault("flagged_items", []).append(item_id)
    for m in progress["mistakes"]:  # 被报告的“自己的句子”题不再出现，错题改用同类题复习
        if m.get("item") and m["item"]["id"] == item_id:
            m["personal_done"] = True
    store.save()


# ---------------- 连续学习天数 ----------------

MEANINGFUL_ITEMS = 10


def _qualifies(progress: dict, d) -> bool:
    rec = progress["days"].get(d.isoformat(), {})
    return rec.get("done", rec.get("items", 0)) >= MEANINGFUL_ITEMS


def streak(progress: dict) -> tuple[int, bool]:
    """连续学习天数：每天完成至少 10 题（不含看答案的题）才算；每连续 7 天可以用 1 次“补签”跳过一天。
    今天还没达标时从昨天算起。返回 (天数, 今天是否已达标)。"""
    today = store.study_day()
    met_today = _qualifies(progress, today)
    d = today if met_today else today - timedelta(days=1)
    count = freezes = 0
    for _ in range(3650):
        if _qualifies(progress, d):
            count += 1
        elif freezes < 1 + count // 7 and _qualifies(progress, d - timedelta(days=1)):
            freezes += 1  # 只断了一天、前一天有练习：用补签接上
        else:
            break
        d -= timedelta(days=1)
    return count, met_today


def daily_goal(progress: dict) -> int:
    minutes = (progress.get("profile") or {}).get("minutes_per_day", 20)
    return max(MEANINGFUL_ITEMS, int(minutes * 0.8))


def kc_rule_card(kc: str) -> str:
    return rule_cards().get(kc, "")


FORMAT_LABELS = FORMATS
