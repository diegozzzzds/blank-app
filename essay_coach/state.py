"""会话状态：学习记录（project）、与输入框双向绑定的字段、导入导出。

Streamlit 在切换页面时会清除不再渲染的输入框状态，所以输入内容另存一份到
project["fields"]，再次进入页面时用它恢复输入框。输入框的 key 按页面区分：
多个页面可以绑定同一个字段（如作文题目），切换页面时新页面的输入框会从
project["fields"] 读到最新值，而不会和上一个页面残留的同名输入框状态冲突。
"""

import json
from datetime import datetime

import streamlit as st

FIELD_PREFIX = "w_"


def _new_project() -> dict:
    return {
        "fields": {},          # 所有绑定输入框的内容
        "drafts": [],          # 每次批改的稿件：text / grading / comparison / rubric / created
        "lessons_done": [],    # 已完成的课程 id
        "exercise_feedback": {},  # 课程 id -> 最近一次练习反馈
        "brainstorm": None,
        "outline_review": None,
        "model_outline": None,
        "chat": [],            # 写作导师对话：{"role", "content"}
    }


def project() -> dict:
    if "project" not in st.session_state:
        st.session_state.project = _new_project()
    return st.session_state.project


def widget_key(name: str) -> str:
    return f"{FIELD_PREFIX}{st.session_state.get('current_page', '')}__{name}"


def bound(widget, name: str, label: str, default=None, **kwargs):
    """渲染一个与 project["fields"][name] 绑定的输入组件，返回当前值。"""
    key = widget_key(name)
    fields = project()["fields"]
    if key not in st.session_state:
        st.session_state[key] = fields.get(name, default)
    value = widget(label, key=key, **kwargs)
    fields[name] = value
    return value


def get_field(name: str, default=None):
    return project()["fields"].get(name, default)


def set_field(name: str, value) -> None:
    """修改绑定字段。只能在按钮回调里、或输入框渲染之前调用。"""
    project()["fields"][name] = value
    st.session_state[widget_key(name)] = value


def reset_field(name: str, value) -> None:
    """修改绑定字段并让输入框在下次渲染时重新读取。任何时候都可以调用。"""
    project()["fields"][name] = value
    for key in [k for k in st.session_state if str(k).startswith(FIELD_PREFIX) and str(k).endswith(f"__{name}")]:
        del st.session_state[key]


def add_draft(text: str, rubric: str, grading: dict, comparison: dict | None = None) -> dict:
    drafts = project()["drafts"]
    draft = {
        "version": len(drafts) + 1,
        "text": text,
        "rubric": rubric,
        "grading": grading,
        "comparison": comparison,
        "created": datetime.now().strftime("%Y-%m-%d %H:%M"),
    }
    drafts.append(draft)
    return draft


def latest_draft() -> dict | None:
    drafts = project()["drafts"]
    return drafts[-1] if drafts else None


def export_json() -> str:
    return json.dumps(project(), ensure_ascii=False, indent=2)


def _clear_widget_keys() -> None:
    for key in [k for k in st.session_state if str(k).startswith(FIELD_PREFIX)]:
        del st.session_state[key]


def import_json(raw: bytes) -> None:
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict) or "drafts" not in data:
        raise ValueError("这不是 EssayCoach 导出的学习记录文件。")
    fresh = _new_project()
    fresh.update(data)
    st.session_state.project = fresh
    _clear_widget_keys()


def reset() -> None:
    st.session_state.project = _new_project()
    _clear_widget_keys()
