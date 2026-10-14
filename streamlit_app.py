import streamlit as st

from essay_coach import ai, state
from essay_coach.prompts import FEEDBACK_LANGS, LEVELS, TEACH_MODES

st.set_page_config(page_title="EssayCoach · AI 写作教练", page_icon="✍️", layout="wide")
state.project()

pages = {
    "开始": [
        st.Page("app_pages/home.py", title="首页 · 学习路径", icon="🏠", default=True),
    ],
    "学": [
        st.Page("app_pages/lessons.py", title="写作课堂", icon="📚"),
    ],
    "练": [
        st.Page("app_pages/outline.py", title="大纲教练", icon="🧭"),
        st.Page("app_pages/grade.py", title="写作与 AI 批改", icon="✍️"),
        st.Page("app_pages/revise.py", title="修改工坊", icon="🔁"),
    ],
    "问": [
        st.Page("app_pages/tutor.py", title="写作导师", icon="💬"),
    ],
}
nav = st.navigation(pages)
st.session_state.current_page = nav.url_path or "home"


def _on_import() -> None:
    upload = st.session_state.get("import_file")
    if upload is None:
        return
    try:
        state.import_json(upload.getvalue())
        st.session_state.import_message = ("success", "已导入学习记录。")
    except (ValueError, UnicodeDecodeError) as e:
        st.session_state.import_message = ("error", f"导入失败：{e}")


with st.sidebar:
    st.markdown("### ⚙️ 设置")
    if not ai.api_key() or st.session_state.get("api_key_input"):
        st.text_input("Anthropic API Key", type="password", key="api_key_input",
                      help="也可以在 .streamlit/secrets.toml 或环境变量中设置 ANTHROPIC_API_KEY。")
    st.caption("🟢 AI 已连接" if ai.is_ready() else "⚪ 未配置 API Key：可以学习课程，AI 功能暂不可用")

    st.selectbox("我的水平", LEVELS, index=1, key="level")
    st.selectbox("反馈语言", list(FEEDBACK_LANGS), key="feedback_lang")
    st.radio("教学方式", list(TEACH_MODES), key="teach_mode",
             help="引导式：AI 给提示和追问，不替你写；示范式：AI 会给出段落级示范改写。")
    st.segmented_control("AI 思考深度", list(ai.EFFORT_LEVELS), default="标准", key="effort_label",
                         help="越深入，批改越细致，但等待时间更长。")

    with st.expander("💾 学习记录"):
        st.download_button("导出学习记录（JSON）", state.export_json(), file_name="essaycoach_progress.json",
                           mime="application/json", width="stretch")
        st.file_uploader("导入学习记录", type="json", key="import_file", on_change=_on_import)
        if msg := st.session_state.pop("import_message", None):
            getattr(st, msg[0])(msg[1])
        st.button("清空所有记录", on_click=state.reset, width="stretch")
        st.caption("记录只保存在当前浏览器会话中，关闭页面前记得导出。")

nav.run()
