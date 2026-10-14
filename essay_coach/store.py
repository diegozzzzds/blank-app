"""学习记录的存储：保存在浏览器 localStorage（关掉页面再打开不会丢），并支持导出/导入 JSON。

做法（已在多页面应用中测试）：每次运行时在入口调用 sync()：
- 第一次运行从 localStorage 读取记录（浏览器回传前返回 None，页面先显示加载中）；
- 页面里修改记录后调用 save()，下一次运行（或本次运行结束时的 flush()）把数据写回浏览器，
  写入组件一直挂载到浏览器确认为止，避免丢更新。
自动化测试中没有浏览器：预先在 st.session_state["progress"] 放好记录即可。
"""

import copy
import json
from datetime import date, datetime, timezone

import streamlit as st

LS_KEY = "essaycoach.progress.v2"
SCHEMA_VERSION = 2
MAX_LOAD_TRIES = 4

DEFAULT = {
    "version": SCHEMA_VERSION,
    "profile": None,       # 目标考试、目标分数、考试日期、每天时间、水平
    "diagnostic": None,    # 诊断结果
    "plan": None,          # AI 生成并经过校验的学习大纲
    "kc": {},              # 技能点状态：掌握度、复习卡片……
    "items": {},           # 题目难度（Elo）：item_id -> {"b", "n"}
    "ai_items": [],        # AI 生成的新题
    "mistakes": [],        # 错题本
    "attempts": [],        # 作答记录
    "essays": [],          # 作文（含诊断、练习、检测）
    "days": {},            # 每日统计：日期 -> {"items", "solo_correct"}
    "chat": [],            # 写作导师对话
    "focus_kcs": [],       # 最近一篇作文暴露的弱项，刷题时优先
    "flagged_items": [],   # 学生报告有问题的题目，不再出现
}
MAX_ATTEMPTS = 3000
MAX_AI_ITEMS = 500


def now() -> datetime:
    return datetime.now(timezone.utc)


def today() -> str:
    return date.today().isoformat()


def new_progress() -> dict:
    return copy.deepcopy(DEFAULT)


def _migrate(data: dict) -> dict:
    fresh = new_progress()
    if isinstance(data, dict):
        fresh.update({k: v for k, v in data.items() if k in DEFAULT})
    fresh["version"] = SCHEMA_VERSION
    return fresh


def _js_eval(expr: str, key: str):
    from streamlit_js_eval import streamlit_js_eval

    return streamlit_js_eval(js_expressions=expr, key=key)


def sync() -> dict | None:
    """在入口每次运行时调用。返回学习记录；浏览器还没回传时返回 None。"""
    ss = st.session_state
    with st.sidebar:  # 组件 iframe 很小，放在侧边栏不影响主区域布局
        if "progress" not in ss or ss.get("_ls_unavailable"):
            ss["_ls_tries"] = ss.get("_ls_tries", 0) + 1
            raw = _js_eval(f"JSON.stringify({{v: localStorage.getItem({json.dumps(LS_KEY)})}})", "ls_load")
            if raw is None:
                if "progress" in ss:
                    return ss["progress"]  # 仍在等待浏览器：继续用本次会话的记录，暂不写入
                if ss["_ls_tries"] < MAX_LOAD_TRIES:
                    return None
                # 浏览器迟迟没有回应：先用空记录让页面可用，但暂停写入，
                # 避免浏览器其实有旧记录时被这份空记录覆盖
                ss["progress"] = new_progress()
                ss["_ls_unavailable"] = True
                return ss["progress"]
            late = ss.pop("_ls_unavailable", False)
            try:
                stored = json.loads(raw).get("v")
                loaded = _migrate(json.loads(stored)) if stored else None
            except (ValueError, TypeError):
                loaded = None
            if loaded is not None:
                ss["progress"] = loaded
                if late:
                    st.toast("已读取这个浏览器里保存的学习记录。")
            elif "progress" not in ss:
                ss["progress"] = new_progress()
        ss["_ls_mounted_ver"] = None  # 本次运行还没有挂载写入组件
        flush()
    return ss["progress"]


def flush() -> None:
    """把未确认的修改写回浏览器。入口在运行开始（sync）和结束时各调用一次，同一版本每次运行只挂载一次。"""
    ss = st.session_state
    pending = ss.get("_ls_pending")
    if not pending or pending[0] == ss.get("_ls_mounted_ver") or ss.get("_ls_unavailable"):
        return
    ver, payload = pending
    ss["_ls_mounted_ver"] = ver
    ok = _js_eval(f"localStorage.setItem({json.dumps(LS_KEY)}, {json.dumps(payload)}); 1", f"ls_save_{ver}")
    if ok == 1 and ss.get("_ls_pending", (None,))[0] == ver:
        del ss["_ls_pending"]


def progress() -> dict:
    ss = st.session_state
    if "progress" not in ss:
        ss["progress"] = new_progress()
    return ss["progress"]


def save() -> None:
    """标记学习记录已修改，稍后写回浏览器。"""
    ss = st.session_state
    p = progress()
    p["attempts"] = p["attempts"][-MAX_ATTEMPTS:]
    if len(p["ai_items"]) > MAX_AI_ITEMS:
        keep = {m.get("item_id") for m in p["mistakes"] if not m.get("retired")}
        extra = len(p["ai_items"]) - MAX_AI_ITEMS
        dropped = 0
        kept = []
        for it in p["ai_items"]:
            if dropped < extra and it["id"] not in keep:
                dropped += 1
                continue
            kept.append(it)
        p["ai_items"] = kept
    ver = ss.get("_ls_ver", 0) + 1
    ss["_ls_ver"] = ver
    ss["_ls_pending"] = (ver, json.dumps(p, ensure_ascii=False))


def export_json() -> str:
    return json.dumps(progress(), ensure_ascii=False, indent=1)


def import_json(raw: bytes) -> None:
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict) or "kc" not in data or "attempts" not in data:
        raise ValueError("这不是 EssayCoach 的学习记录文件。")
    st.session_state["progress"] = _migrate(data)
    save()


def reset() -> None:
    st.session_state["progress"] = new_progress()
    save()
