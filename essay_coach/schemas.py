"""AI 结构化输出的数据模型（用于 JSON Schema 约束输出格式）。

所有字段都设为必填、不设默认值，范围要求写在 description 里，
因为结构化输出不支持数值范围约束；越界的值在代码中再做校正。
"""

from typing import Literal

from pydantic import BaseModel, Field

# ---------- 批改 ----------

Category = Literal["grammar", "vocabulary", "logic", "structure", "evidence", "style", "mechanics"]
Severity = Literal["major", "minor", "suggestion"]


class CriterionScore(BaseModel):
    name: str = Field(description="评分项名称，与评分标准中的名称和顺序完全一致")
    score: float = Field(description="该项得分，介于 0 和该项满分之间")
    comment: str = Field(description="评分理由：结合原文说明为什么是这个分数、离下一档还差什么")


class Annotation(BaseModel):
    quote: str = Field(description="从学生原文中逐字复制的片段（3–25 个词），必须与原文完全一致，用于高亮定位")
    category: Category
    severity: Severity = Field(description="major=影响得分的重要问题，minor=次要错误，suggestion=可以更好的建议")
    issue: str = Field(description="问题是什么、为什么是问题")
    suggestion: str = Field(description="怎么改：修改方向或示例改写")


class ParagraphFeedback(BaseModel):
    paragraph: int = Field(description="段落编号，对应原文中的 [P1]、[P2]……")
    role: str = Field(description="这一段在文中的作用，如“开头段”“主体段 1”“结尾段”")
    main_idea: str = Field(description="用一句话概括这段实际表达的中心（反向大纲）")
    feedback: str = Field(description="针对这一段的具体反馈")


class RevisionTask(BaseModel):
    title: str = Field(description="简短的修改任务标题")
    detail: str = Field(description="具体要做什么、在哪里改、改到什么程度算完成")
    focus: Category


class GradingResult(BaseModel):
    level_label: str = Field(description="一个简短的水平标签，如 “Band 6.5”“B+ 良好”“4/6”")
    summary: str = Field(description="总体评价，3–5 句话")
    criteria: list[CriterionScore]
    strengths: list[str] = Field(description="2–4 条真正做得好的地方，具体到原文")
    annotations: list[Annotation] = Field(description="5–15 条批注，按重要性排序")
    paragraph_feedback: list[ParagraphFeedback] = Field(description="每一段一条")
    revision_tasks: list[RevisionTask] = Field(description="3–5 个修改任务，按优先级排序，最重要的在前")


# ---------- 修改稿对比 ----------

class TaskCheck(BaseModel):
    task: str = Field(description="上一版的修改任务标题")
    status: Literal["done", "partial", "not_done"]
    comment: str = Field(description="这一任务完成得怎么样，结合新稿原文说明")


class RevisionComparison(BaseModel):
    overall: str = Field(description="对这次修改的总体评价，2–4 句话")
    improvements: list[str] = Field(description="新稿中具体的进步")
    regressions: list[str] = Field(description="新稿中变差或新出现的问题；没有则为空列表")
    task_checks: list[TaskCheck]


class RevisionResult(BaseModel):
    comparison: RevisionComparison
    grading: GradingResult


# ---------- 大纲 ----------

class Angle(BaseModel):
    stance: str = Field(description="一个可选的立场或切入角度（英文一句话）")
    core_reason: str = Field(description="支持这个立场的核心理由")
    evidence_ideas: list[str] = Field(description="2–3 个可以用的论据方向（不要编造精确数据）")


class Brainstorm(BaseModel):
    prompt_analysis: str = Field(description="题目拆解：话题、指令词要求、范围/限制词")
    key_terms: list[str] = Field(description="需要界定或注意的关键词")
    angles: list[Angle] = Field(description="2–3 个不同的立场/角度")
    guiding_questions: list[str] = Field(description="3–5 个帮助学生自己思考的问题")
    pitfalls: list[str] = Field(description="这道题容易跑题或失分的地方")


class SectionReview(BaseModel):
    section: str = Field(description="大纲中的部分，如 “Thesis”“Body 1”“Conclusion”")
    rating: Literal["strong", "ok", "weak"]
    comment: str
    suggestion: str


class OutlineReview(BaseModel):
    readiness: int = Field(description="0–100，大纲可以直接开始写作的成熟度")
    overall: str = Field(description="总体评价，2–4 句话")
    thesis_check: str = Field(description="thesis 是否回答题目、是否可辩论、是否具体")
    sections: list[SectionReview]
    logic_issues: list[str] = Field(description="论点重叠、逻辑跳跃、与 thesis 不一致等问题；没有则为空列表")
    guiding_questions: list[str] = Field(description="2–4 个引导学生完善大纲的问题")


class BodyPlan(BaseModel):
    topic_sentence: str
    evidence: list[str]
    analysis: str = Field(description="这段的分析思路：论据如何支撑论点")


class ModelOutline(BaseModel):
    thesis: str
    hook: str
    background: str
    body: list[BodyPlan]
    counterargument: str
    rebuttal: str
    conclusion: str
    teaching_notes: list[str] = Field(description="2–4 条说明：这个大纲为什么这样设计，学生可以学到什么")


# ---------- 课堂练习 ----------

class ExerciseFeedback(BaseModel):
    stars: int = Field(description="1–5 星评分")
    verdict: str = Field(description="一句话总评")
    strengths: list[str]
    issues: list[str] = Field(description="需要改进的地方，按重要性排序")
    next_step: str = Field(description="下一步具体怎么改")
    example: str = Field(description="示范答案（遵循教学模式的要求）")
    example_note: str = Field(description="示范答案的说明：好在哪里")
