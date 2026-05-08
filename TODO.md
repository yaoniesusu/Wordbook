# Wordbook 迭代 Todo

## ✅ 已完成（38 项）

### 🔴 核心
- [x] 多源翻译并行 — Lingva + LibreTranslate + MyMemory，详情页显示来源+置信度
- [x] 长句拆分 — 6词+打散，停用词丢弃，词形还原，原句为公共例句
- [x] 10级色阶熟悉度 — 侧边栏圆点按 reviewCount 10级颜色渐变
- [x] SM-2 间隔重复 — Easiness Factor 动态调整复习间隔
- [x] WordbookStore 拆分 — PersistenceController / ReviewEngine / FuzzySearchEngine
- [x] 模糊搜索 — Levenshtein 编辑距离容错

### 🟡 重要
- [x] macOS TTS 发音 — 详情页/复习页喇叭按钮朗读
- [x] 反向复习 — toggle 看中文+听发音→回忆英文
- [x] 拼写模式 — 看中文+听发音，输入框打出英文
- [x] 复习批次自动补充 — 做完一批自动加载下一批
- [x] 每日目标圆环 — 侧边栏复习进度环
- [x] 定时提醒 — 本地通知每天定时提醒复习
- [x] 标签自动补全 — 输入标签时提示已有标签
- [x] 批量操作 — 选择模式，批量标记掌握/删除
- [x] 菜单栏小组件 — MenuBarExtra 到期数+快捷操作
- [x] 拖拽添加 — 任意App拖文本到窗口即添加
- [x] 例句关联展示 — 同例句单词互相可见

### 🟢 加分
- [x] Swift Charts 统计图表 — 7天柱状图+掌握分布图
- [x] 整句挖空复习（Cloze Deletion） — 例句中单词变填空
- [x] 导出 Anki TSV — 兼容 Anki 间隔重复
- [x] 开机自启动 — SMAppService LoginItem
- [x] 键盘导航 — 上下箭头切换词条

### 🔧 技术债
- [x] 撤销 Cmd+Z — undo 栈 20 步
- [x] 词典查询超时 — 8s 超时
- [x] 词典中文释义管道 — 英文释义→自动翻译中文
- [x] Konami 键码修复 — UInt16→NSEvent.SpecialKey
- [x] batchTranslate 分隔符 — ‖‖ 全角双竖线
- [x] 设置独立窗口 — Settings scene (Cmd+,)
- [x] 标准菜单命令 — File/Edit 菜单
- [x] 词条排序 — 最新/A-Z/待复习优先
- [x] 历史快照 — 每日自动快照，保留30天，可回退

### 🗑️ 清理
- [x] clipboardRepeatCount 移除
- [x] 模糊回忆开关移至复习页
- [x] "更多"菜单拆分
- [x] 逐词释义已优化（限量3条+异步翻译）
- [x] 英文回退逻辑已简化

---

## 🔧 进行中

- [ ] **单词本分组** — 生词 / 已会 / 巩固 三个默认组，侧边栏展示
- [ ] **关联词族** — decide→decision 同根词自动识别关联
- [ ] **词汇频率标注** — COCA 高频词标注

---

## ⬜ 待定（低优先级）

- [ ] 右键 Services 集成
- [ ] 收录历史页可点击跳转
- [ ] MyMemory 邮箱→钥匙串
- [ ] 无障碍完善（已加基础 label）
- [ ] i18n 准备
- [ ] 每日复习伪进度修复
