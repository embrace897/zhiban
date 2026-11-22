# Milk Dragon_数据库设计说明书

版本3.4 / 2026-11-22 / 设计详化稿

## Milk Dragon 数据库设计说明书

版本3.4 / 2026年11月22日 / 设计详化稿

阅读索引：第1至4章为设计原则、实体关系和映射。第5章逐表解释字段与约束。第6至11章说明事务、索引、备份与集成。第12至18章展开业务写入、状态、查询、生命周期和验收。

附件schema.sql为可执行设计基线，已在内存SQLite中验证建表，不代表线上数据库已迁移。

版本记录：V3.3列出19张表的主外键与对象映射。V3.4在此基础上细化数据约束、事务边界、备份恢复与验证。

## 1 引言、参考与术语

参考：GB/T 8567—2006《计算机软件文档编制规范》。国家标准平台：https://openstd.samr.gov.cn/bzgk/std/newGbInfo?hcno=84C42B6277D2714B7176B10C6E6B1A44 。按系统/子系统设计与数据库顶层设计主题裁剪组织，未声称逐条符合性认证。公开需求基线为第一次作业博客https://www.cnblogs.com/embrace897/p/23594772（2026-11-21核对），沿用FR01—20及原优先级；V2.0报告为辅助材料；本设计为V3.4详化稿。

UML（Unified Modeling Language，统一建模语言）；ER（Entity Relationship，实体关系）；API（Application Programming Interface，应用程序接口）；RAG（Retrieval-Augmented Generation，检索增强生成）；MCP（Model Context Protocol，模型上下文协议）；Skill（场景处理规范）；PK（Primary Key，主键）；FK（Foreign Key，外键）；ORM（Object Relational Mapping，对象关系映射）；DDL（Data Definition Language，数据定义语言）；UTC（Coordinated Universal Time，协调世界时）；WAL（Write-Ahead Logging，预写日志）；CAS（Compare And Set，比较并更新）；JSON（JavaScript Object Notation，数据交换表示）。 FR（Functional Requirement，功能需求），P0/P1/P2（核心、次优先、扩展），ID（Identifier，标识），PDF（Portable Document Format，便携式文档格式），UI（User Interface，用户界面），HTTPS（Hypertext Transfer Protocol Secure，安全超文本传输协议），SQL（Structured Query Language，结构化查询语言），P95（第95百分位）。SSDD为系统及子系统设计说明书的文档标识缩写，DB为Database（数据库）。

业务库管理身份、通知、计划、执行、提醒、记忆与公共资料。文件正文在受控存储，表保存定位；检索索引是可重建派生数据。

## 2 设计决策与规范

采用SQLite关系模型，开启外键与WAL。内部ID采用服务端生成的文本标识；created_at默认数据库时间。UTC精确时间统一使用带Z的文本格式，日期型使用YYYY-MM-DD并记录时区。

表名为snake_case，实体类为PascalCase。主表与关联表规范化；仅可变计划、差异和证据使用JSON字段，服务端按固定模式校验。禁止从JSON字段动态拼接SQL。

所有者一致性由事务内服务校验，单独外键不能防止跨用户关联。任何关联通知、事务、文件时必须核对两端所属范围；核心测试覆盖跨用户关联。

## 3 概念ER模型

![07-ER图](assets/07-ER图.png)

连线以1:N标识基数；通知与事务为多对多，由关联表消解。其余执行、材料、资料与记忆关系在关系模型中定义。

图为核心概念子集，完整实体以DDL及数据字典为准，不能据图省略确认与审计。

## 4.1 关系数据模型：主键与外键

| 关系表 | 主键 | 外键 → 被引用表 |
|---|---|---|
| users | id | — |
| files | id | owner_id → users.id |
| notices | id | file_id → files.id<br>owner_id → users.id |
| drafts | id | notice_id → notices.id |
| affairs | id | owner_id → users.id |
| affair_notices | affair_id, notice_id | notice_id → notices.id<br>affair_id → affairs.id |
| events | id | affair_id → affairs.id<br>owner_id → users.id |
| checklist_items | id | affair_id → affairs.id |
| plans | id | affair_id → affairs.id<br>owner_id → users.id |
| confirmations | id | actor_id → users.id<br>plan_id → plans.id |

通知与事务通过affair_notices相连。该关联表使用两个外键组成联合主键。

## 4.2 关系数据模型：执行、资料与证据

| 关系表 | 主键 | 外键 → 被引用表 |
|---|---|---|
| executions | id | plan_id → plans.id |
| reminders | id | event_id → events.id |
| knowledge_documents | id | file_id → files.id |
| knowledge_chunks | id | document_id → knowledge_documents.id |
| memory_items | id | owner_id → users.id |
| changes | id | plan_id → plans.id<br>notice_id → notices.id<br>affair_id → affairs.id |
| audit_logs | id | actor_id → users.id |
| event_sources | event_id, draft_id, field_name | draft_id → drafts.id<br>event_id → events.id |
| artifacts | id | file_id → files.id<br>execution_id → executions.id<br>affair_id → affairs.id<br>owner_id → users.id |

外键列的必填性见数据字典。带唯一约束的版本、幂等键和产物关联见建表脚本。

## 4.3 实体类与关系表映射

| 实体类 | 关系表 | 实体类 | 关系表 |
|---|---|---|---|
| User | users | Execution | executions |
| File | files | Reminder | reminders |
| Notice | notices | KnowledgeDocument | knowledge_documents |
| NoticeDraft | drafts | KnowledgeChunk | knowledge_chunks |
| Affair | affairs | MemoryItem | memory_items |
| AffairNotice | affair_notices | NoticeChange | changes |
| Event | events | AuditLog | audit_logs |
| ChecklistItem | checklist_items | EventSource | event_sources |
| ActionPlan | plans | Artifact | artifacts |
| Confirmation | confirmations | — | — |

映射采用显式持久化转换。列的类型、主外键、默认值与可空性以第4.1、4.2节和第5章为准。

## 4.4 关键属性的对象关系映射

| 实体类属性 | 数据库列 | 转换规则 |
|---|---|---|
| Affair.ownerId / revision | affairs.owner_id / revision | 身份来自服务端，版本用于冲突检查 |
| Notice.fileId | notices.file_id | 上传附件时设置，纯文本时允许空值 |
| Event.dueAt / dateValue | events.due_at / date_value | 按precision控制时间精度，未知时两个字段均空 |
| AffairNotice.affairId / noticeId | affair_notices.affair_id / notice_id | 联合主键映射为关联对象的复合标识 |
| ActionPlan.operations | plans.operations_json | 对象数组校验后序列化，读取时解析 |
| Confirmation.planRevision | confirmations.plan_revision | 与plan_id组成唯一键，同一计划版本仅有一条确认 |
| Execution.stepKey / result | executions.step_key / result_json | 步骤键唯一，结果由执行器校验后序列化 |
| EventSource.confirmedValue | event_sources.confirmed_value | 以事项、草稿、字段名为联合标识，保存核对结果 |
| Artifact.fileId / executionId | artifacts.file_id / execution_id | 关联真实文件和执行步骤，组合唯一 |
| KnowledgeDocument.indexStatus | knowledge_documents.index_status | 读写资料索引状态，检索仅使用就绪且有效的资料 |

持久化层将对象中的驼峰属性显式映射到数据库下划线列名。每表完整字段及约束见第5章。

## 5 数据字典 / users

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 内部用户标识 |
| wx_subject | TEXT NOT NULL UNIQUE | 平台身份映射，禁止客户端指定 |
| role | TEXT NOT NULL CHECK(role IN ('student','maintainer','admin')) | 角色 |
| status | TEXT NOT NULL DEFAULT 'active' | 账号状态 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

wx_subject用于平台身份映射，角色及启停状态由服务端管理。个人业务读写以内部用户标识为准。

## 5 数据字典 / files

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 实体标识 |
| owner_id | TEXT NOT NULL REFERENCES users(id) | 所属用户 |
| storage_key | TEXT NOT NULL UNIQUE | 存储定位，不是公开链接 |
| sha256 | TEXT NOT NULL | 内容摘要 |
| mime | TEXT NOT NULL | 核验的格式 |
| size_bytes | INTEGER NOT NULL CHECK(size_bytes>=0) | 文件大小 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

文件正文由storage_key定位，sha256保存内容校验值。即使内容相同，也要分别核对授权归属。

## 5 数据字典 / notices

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 实体标识 |
| owner_id | TEXT NOT NULL REFERENCES users(id) | 所属用户 |
| file_id | TEXT REFERENCES files(id) | 附件可空，文本通知无附件 |
| source | TEXT NOT NULL | 来源描述 |
| published_at | TEXT | 发布时间，可空 |
| raw_text | TEXT | 原文 |
| status | TEXT NOT NULL DEFAULT 'pending' | 解析状态 |
| revision | INTEGER NOT NULL DEFAULT 1 | 版本 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

附件通知引用file_id，纯文本可留空。revision作为解析与核对的并发标记。

## 5 数据字典 / drafts

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 草稿标识 |
| notice_id | TEXT NOT NULL REFERENCES notices(id) | 所属通知 |
| revision | INTEGER NOT NULL | 草稿版本 |
| fields_json | TEXT NOT NULL | 字段值及明确/推导/缺项状态 |
| evidence_json | TEXT NOT NULL | 原文片段/页码/可选区域 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：UNIQUE(notice_id,revision)

每个通知版本对应一条草稿。fields_json记录候选值，evidence_json保存来源定位。

## 5 数据字典 / affairs

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 实体标识 |
| owner_id | TEXT NOT NULL REFERENCES users(id) | 所属用户 |
| title | TEXT NOT NULL | 事务标题 |
| status | TEXT NOT NULL DEFAULT 'preparing' | 事务状态 |
| revision | INTEGER NOT NULL DEFAULT 1 | 版本 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

事务状态preparing作为默认。产生持久化变化时更新revision，既有方案用它检测并发修改。

## 5 数据字典 / affair_notices

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| affair_id | TEXT NOT NULL REFERENCES affairs(id) | 事务 |
| notice_id | TEXT NOT NULL REFERENCES notices(id) | 通知 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：PRIMARY KEY(affair_id,notice_id)

同一对事务和通知只关联一次。写入前核对两端的owner_id一致。

## 5 数据字典 / events

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 实体标识 |
| owner_id | TEXT NOT NULL REFERENCES users(id) | 所属用户 |
| affair_id | TEXT NOT NULL REFERENCES affairs(id) | 所属事务 |
| title | TEXT NOT NULL | 标题 |
| kind | TEXT NOT NULL CHECK(kind IN ('activity','deadline','step')) | 类型 |
| due_at | TEXT | UTC时间，可空 |
| date_value | TEXT | 日期型值，可空 |
| precision | TEXT NOT NULL CHECK(precision IN ('date','minute','unknown')) | 时间精度 |
| timezone | TEXT NOT NULL DEFAULT 'Asia/Shanghai' | 展示时区 |
| status | TEXT NOT NULL DEFAULT 'todo' | 事项状态 |
| revision | INTEGER NOT NULL DEFAULT 1 | 并发版本 |
| start_at | TEXT | 活动开始UTC时间 |
| end_at | TEXT | 活动结束UTC时间，可空但不能擅自推断时长 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：CHECK((precision='date' AND date_value IS NOT NULL AND due_at IS NULL) OR (precision='minute' AND due_at IS NOT NULL AND date_value IS NULL) OR (precision='unknown' AND due_at IS NULL AND date_value IS NULL)); CHECK(end_at IS NULL OR (start_at IS NOT NULL AND end_at>start_at)); CHECK(kind='activity' OR (start_at IS NULL AND end_at IS NULL))

时间精度属于业务事实。date仅存日历日期，minute存精确时刻，unknown不写这两列。起止时刻仅用于活动。

## 5 数据字典 / checklist_items

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 条目标识 |
| affair_id | TEXT NOT NULL REFERENCES affairs(id) | 事务 |
| title | TEXT NOT NULL | 材料或准备步骤 |
| done | INTEGER NOT NULL DEFAULT 0 CHECK(done IN (0,1)) | 完成状态 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

done保存材料完成情况，所有权经affair_id追溯。变更计划保留与变化无关的完成记录。

## 5 数据字典 / plans

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 实体标识 |
| owner_id | TEXT NOT NULL REFERENCES users(id) | 所属用户 |
| affair_id | TEXT NOT NULL REFERENCES affairs(id) | 事务 |
| revision | INTEGER NOT NULL | 计划版本 |
| operations_json | TEXT NOT NULL | 动作和目标版本快照 |
| status | TEXT NOT NULL DEFAULT 'draft' | 计划状态 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

写入操作列表与目标版本。登记执行后冻结操作及版本，后续调整使用新的计划标识。

## 5 数据字典 / confirmations

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 确认标识 |
| plan_id | TEXT NOT NULL REFERENCES plans(id) | 确认计划 |
| plan_revision | INTEGER NOT NULL | 确认版本 |
| actor_id | TEXT NOT NULL REFERENCES users(id) | 确认人 |
| digest | TEXT NOT NULL | 操作摘要 |
| consumed | INTEGER NOT NULL DEFAULT 0 CHECK(consumed IN (0,1)) | 是否消费 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：UNIQUE(plan_id,plan_revision)

同一计划版本只接受一条确认。消费与步骤登记在同一事务，避免已确认但找不到执行记录。

## 5 数据字典 / executions

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 执行标识 |
| plan_id | TEXT NOT NULL REFERENCES plans(id) | 所属计划 |
| step_key | TEXT NOT NULL UNIQUE | 稳定步骤幂等键 |
| tool | TEXT NOT NULL | 工具标识 |
| status | TEXT NOT NULL DEFAULT 'queued' | 执行状态 |
| result_json | TEXT | 结果或错误摘要 |
| lease_until | TEXT | 执行租约到期 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

每个操作一条记录。step_key跨重放稳定，结果状态及租约决定能否续跑或重试。

## 5 数据字典 / reminders

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 提醒标识 |
| event_id | TEXT NOT NULL REFERENCES events(id) | 对应事项 |
| fire_at | TEXT NOT NULL | UTC触发时间 |
| status | TEXT NOT NULL DEFAULT 'pending' | 待触发/已产生/取消 |
| read_at | TEXT | 用户阅读时间 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

与事项关联。到期后记录产生状态，从read_at判断阅读情况，站内查询须核验事项所属用户。

## 5 数据字典 / knowledge_documents

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 资料标识 |
| file_id | TEXT NOT NULL REFERENCES files(id) | 原始资料 |
| institution | TEXT NOT NULL | 机构范围 |
| version | TEXT NOT NULL | 文档版本 |
| source_url | TEXT | 来源 |
| valid_until | TEXT | 有效期 |
| status | TEXT NOT NULL DEFAULT 'draft' | 待审/发布/停用 |
| department | TEXT | 部门范围，可空代表机构级 |
| audience | TEXT NOT NULL DEFAULT 'all' | 适用人群 |
| valid_from | TEXT | 生效时间 |
| index_status | TEXT NOT NULL DEFAULT 'pending' | 索引就绪状态 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

status描述发布状态，index_status描述检索索引状态。两者和有效期共同决定资料是否进入检索。

## 5 数据字典 / knowledge_chunks

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 分段标识 |
| document_id | TEXT NOT NULL REFERENCES knowledge_documents(id) | 来源文档 |
| ordinal | INTEGER NOT NULL | 段序 |
| content | TEXT NOT NULL | 分段文本 |
| locator | TEXT NOT NULL | 页码或段落定位 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：UNIQUE(document_id,ordinal)

以资料版本和ordinal定位稳定分段。locator用于展示原文页码或章节。

## 5 数据字典 / memory_items

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 实体标识 |
| owner_id | TEXT NOT NULL REFERENCES users(id) | 所属用户 |
| content | TEXT NOT NULL | 用户确认的长期信息 |
| source_ref | TEXT NOT NULL | 来源会话或人工输入 |
| revision | INTEGER NOT NULL DEFAULT 1 | 版本 |
| status | TEXT NOT NULL DEFAULT 'proposed' | 提议/有效/停用/删除 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

只有用户确认的有效记忆可注入新会话。source_ref保留来源标识，修改按revision校验。

## 5 数据字典 / changes

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 变更标识 |
| affair_id | TEXT NOT NULL REFERENCES affairs(id) | 事务 |
| notice_id | TEXT NOT NULL REFERENCES notices(id) | 补充通知 |
| diff_json | TEXT NOT NULL | 字段差异与影响对象 |
| plan_id | TEXT REFERENCES plans(id) | 调整计划 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

记录补充通知及差异，可关联候选计划。比较阶段只写差异记录，正式事项待确认执行。

## 5 数据字典 / audit_logs

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 审计标识 |
| actor_id | TEXT REFERENCES users(id) | 操作身份 |
| action | TEXT NOT NULL | 动作 |
| target_ref | TEXT NOT NULL | 对象引用 |
| request_id | TEXT NOT NULL | 关联请求 |
| summary | TEXT | 不含完整私人正文的摘要 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：无表级附加约束；以DDL和业务校验为准。

保存最小操作摘要。由后台任务触发时actor_id可空，以request_id追踪处理。

## 5 数据字典 / event_sources

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| event_id | TEXT NOT NULL REFERENCES events(id) | 正式事项 |
| draft_id | TEXT NOT NULL REFERENCES drafts(id) | 保留原始解析版本 |
| field_name | TEXT NOT NULL | 来源字段 |
| evidence_json | TEXT NOT NULL | 原文片段和定位 |
| confirmed_value | TEXT NOT NULL | 人工确认后的字段值 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：PRIMARY KEY(event_id,draft_id,field_name)

联合标识由事项、草稿和字段组成。同一正式事项的历次核对可按草稿定位。

## 5 数据字典 / artifacts

| 字段 | 类型与约束 | 含义 |
|---|---|---|
| id | TEXT PRIMARY KEY | 实体标识 |
| owner_id | TEXT NOT NULL REFERENCES users(id) | 所属用户 |
| affair_id | TEXT NOT NULL REFERENCES affairs(id) | 所属事务 |
| execution_id | TEXT NOT NULL REFERENCES executions(id) | 生成步骤 |
| file_id | TEXT NOT NULL REFERENCES files(id) | 真实产物 |
| kind | TEXT NOT NULL | 提纲/材料草稿 |
| status | TEXT NOT NULL DEFAULT 'ready' | 产物状态 |
| created_at | TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP | 创建时间 |

附加约束：UNIQUE(execution_id,file_id)

产物绑定所属用户、事务、执行及实际文件。调用方只能取得通过权限校验的文件下载入口。

## 6 事务、完整性与并发

创建事务：核对草稿版本→验证所属→写入事务/关联/事项/清单→写审计→提交，失败整体回滚。

确认执行：BEGIN IMMEDIATE→读取并核验计划与目标版本→消费确认→登记唯一步骤→提交；后台再运行工具。内部任务写入及执行成功标记同一事务。

资料发布：核对维护权限与元数据→发布状态→异步建立索引；仅发布且索引就绪资料参与新检索。停用时先禁止检索，索引清理可以异步。

外键沿用SQLite默认的NO ACTION（默认阻止提交未解除引用的删除）。清除附件前先检查引用并按顺序解除关联。日期精度由表约束保证，JSON内容由服务层校验。

## 7 索引、规模与性能

ix_events_due用于用户未完成期限查询；ix_reminders_due用于提醒扫描；ix_executions_claim用于任务领取与租约；ix_notices_owner用于通知箱。唯一键负责幂等、草稿版本和文档段序。

试点假设100用户，每人100通知、每通知平均2MB，原件约20GB；平均5事项/通知约5万事项。该容量为规划估算，不能作为实测。

建议分配至少40GB附件空间并另留备份，数据库容量以真实样本测量。普通读取20并发P95目标2秒；索引通过查询计划与压测验证。

## 8 安全、备份与迁移

用户查询强制owner_id过滤；关联字段所属校验与业务写入同一事务。管理员不自动拥有私人文档检索权限。微信凭证与模型密钥不进入业务表明文和日志。

每日采用SQLite一致性备份接口生成快照，连同文件清单、版本及校验值归档；不可只复制活动主库而遗漏WAL。目标恢复点24小时、恢复时间4小时，需演练。

迁移记录schema版本与校验值；先备份、测试迁移、完整性检查再切换。失败恢复旧版本与快照；运行任务先停领并核对外部结果，不重放不明副作用。

在线数据删除后清除索引与缓存；备份拟保留7天，到期清理，最终保留政策待团队确认。

## 9 验证与需求追踪

本次验证：schema.sql在内存SQLite中成功建表并通过foreign_key_check。并发与业务授权尚未实现，不宣称全部通过。

后续：外键错误插入应拒绝；重复step_key应拒绝；未知日期不写精确时刻；过期计划409；跨用户关联403；备份恢复后数量和附件校验一致。

对应需求：FR01权限；FR02-06通知与事务；FR08资料；FR10执行；FR11提醒；FR13记忆；FR14变更；FR16恢复；FR19删除。

评审未决：真实模型与数据库访问库版本、检索实现、资料发布权限、最终保留期及容量。

## 10 证据链、产物及完整关系

![08-扩展ER图](assets/08-扩展ER图.png)

图中展示事务、计划、确认、执行与产物之间的关系。其余关系见第4.1及4.2节的完整外键表。

相同执行产物重复回调由唯一(execution_id,file_id)拒绝；正式字段保存人工确认值与原文出处。时间约束在表级保证结束晚于开始；无结束时间不补默认时长。

## 11 与公开需求的差异及集成边界

第一次作业公开基线：https://www.cnblogs.com/embrace897/p/23594772。目标模型共19表，event_sources与artifacts用于补齐FR04原文核对与FR12真实产物落库，不增加独立用户业务。

资料元数据增加department、audience、valid_from、index_status以落实FR08适用范围及有效期。索引落后或资料停用时先排除检索，后台可重建。

身份与MiniClaw工作区建立内部映射，会话/消息复用现有持久化并加事务关联适配；本文19表是校园业务目标模型，不代表可以直接导入底座覆盖旧表。整合迁移必须用独立命名空间或适配仓储，先检查现有表结构。

JSON字段保存操作快照而不复制实时任务状态；时间比较统一UTC格式；本轮仅验证DDL、唯一约束、时间约束与外键，跨用户授权和模型效果仍待实现。

## 12 数据域、记录来源与约束边界

| 数据域 | 涉及关系 | 写入来源及约束 |
|---|---|---|
| 身份及原件 | users / files / notices / drafts | 用户提交原文，后台追加草稿。原文与人工确认值分别存储 |
| 事务及办理内容 | affairs / affair_notices / events / checklist_items / reminders | 核对或确认执行后才写正式事项。同一事务内业务目标归属一致 |
| 计划、追溯及产物 | plans / confirmations / executions / changes / event_sources / artifacts | 计划冻结后按分步结果追溯。文件存在且归属一致后才登记ready |
| 资料、偏好及审计 | knowledge_documents / knowledge_chunks / memory_items / audit_logs | 资料须审核，长期偏好由用户确认，审计只留必要摘要 |

数据库约束覆盖主外键、唯一性、部分枚举与时间列组合。服务层负责非空业务标识、操作权限、跨表归属、状态转换、有效期和JSON内容。普通SQLite表的文本主键需额外防止空值，当前建表脚本由写入层校验，正式迁移可显式补充NOT NULL。

每个连接初始化后启用foreign_keys，并检查该配置生效。引用存在不能证明属于当前用户，连接查询需按所有权逐层约束。

## 13 核对、差异与执行的事务边界

| 场景 | 短事务中的读写步骤 | 失败与重入 |
|---|---|---|
| 确认通知 | 查通知及草稿归属和版本，按目标事务确认同一关联，写事项、字段来源、材料清单及审计 | 版本冲突回退全部写入。同一提交标识的重复请求返回已有事务 |
| 比较补充通知 | 创建changes及候选计划，保存旧值、新值和目标版本快照 | 已有正式任务继续按原状态展示，比较流程只落差异和候选计划 |
| 提交执行 | 在BEGIN IMMEDIATE中检查归属和确认绑定，已登记时回原结果。首次提交校验目标版本、消费确认、登记步骤 | 任何一步失败均回滚。相同计划与操作的步骤键唯一 |
| 工具结果写回 | 核验租约。内部业务更新、版本增加及成功状态同一事务。外部产物校验后登记files及artifacts | 未知外部结果保留待核实状态，避免重复生成或提交 |
| 通知变更应用 | 只更新变更方案涉及的事项和待触发提醒，更新目标版本并记录结果 | 发现目标版本变化时停止该步并提示重新核对 |

每次写事务在持锁前完成可提前完成的处理。模型推理、网络工具调用和大文件写入均在短事务之外。遇到数据库忙时采用有限重试，重试须沿用合法请求的稳定标识。

首次核对时可在审计动作的request_id和摘要中记录服务端接受的提交标识、草稿版本及目标事务标识。短事务按本人和提交标识回查成功记录，仅在确认同一业务输入时返回既有结果。

## 14 状态迁移与任务恢复

| 对象 | 设计状态与迁移 | 关键约束 |
|---|---|---|
| 通知 | pending → ready 或 failed。失败经用户重试回pending | 单解析进程消费pending。以通知版本保护草稿提交 |
| 计划 | draft → confirmed → submitted。登记后从步骤聚合结果 | 已登记方案保持不可变。修订时新建计划标识 |
| 执行步骤 | queued → running → succeeded / failed / uncertain。明确失败且安全可重试时回queued | 使用固定步骤键。以领取时租约值做条件更新，旧工作进程不能覆盖新结果 |
| 提醒 | pending → emitted 或 cancelled | 到期写emitted，阅读只改read_at。已产生提醒保留历史 |
| 资料与索引 | draft → published → disabled。索引独立pending → ready/failed | 先校验可检索性再排序。停用或索引失败后从新检索排除 |
| 记忆 | proposed → confirmed → disabled / deleted | 写入由用户确认，停用和删除后从新会话排除 |

上述状态名是服务层设计约定。首期数据库仅对部分枚举设置约束，各状态转换仍由业务服务校验。在没有可信结果时，过期外部步骤进入uncertain，恢复前核对请求标识及文件。

## 15 查询、时间约定与索引验证

按本人范围及状态分页查询通知和事项。列表使用稳定排序，翻页游标由排序值与记录标识共同确定。精确时刻使用固定精度的UTC字符串，日期精度单独保存。created_at使用数据库默认值，展示前解析并按事件时区转化，避免混合格式直接比较。

| 现有索引 | 样例访问谓词 | 本地查询计划 |
|---|---|---|
| ix_events_due | owner_id与status相等，按due_at范围过滤 | 使用该索引 |
| ix_reminders_due | status相等，fire_at早于扫描上限 | 使用该索引 |
| ix_executions_claim | status相等，lease_until早于租约截止 | 使用该索引 |
| ix_notices_owner | owner_id与status相等 | 使用该索引 |

使用现有schema.sql在内存SQLite中执行EXPLAIN QUERY PLAN，验证访问谓词与联合索引列顺序匹配。上线前使用接近试点规模的数据检查扫描、临时排序、后台领取吞吐及锁等待，再决定索引调整。

## 16 文件一致性、保留与清理

| 阶段 | 数据操作 | 检查点 |
|---|---|---|
| 上传或生成 | 先写暂存并校验大小、类型和摘要，再移动到受控文件区，最后登记文件引用 | 登记失败清理孤立文件，避免入库记录指向不可读文件 |
| 下载 | 从业务对象校验关联、归属、可见状态，再解析storage_key | 禁止由客户端直接选取存储路径 |
| 逻辑删除 | 先解除检索与客户端可见性，同步失效缓存 | 检查文件仍否被通知、产物或知识资料引用 |
| 物理清理 | 在保留周期结束后由任务清理已无引用的正文、索引及副本 | 审计保留必要摘要。备份过期后按对应政策清除 |

若文件持久化与数据库登记之间发生崩溃，用待核实状态与后台对账处理。对账以文件摘要、稳定存储标识和业务关联为准。历史备份的删除与恢复须遵循已确认的保留策略。

## 17 备份、恢复与迁移验收

试点规划恢复点24小时、恢复时间4小时。快照包含数据库、与快照匹配的附件清单和摘要、数据库结构版本。备份时暂停附件删除并保留快照引用的文件，核实清单可恢复后再结束。

恢复演练在隔离环境完成。校验快照和附件摘要，通过integrity_check、foreign_key_check和样例业务读写检查，再重建资料索引。恢复后的队列先停领，盘点已发出但未确认结果的操作。

迁移前锁定目标结构版本和脚本摘要，用脱敏样本演练升级。旧库先备份。若迁移失败，恢复迁移前的数据库及附件清单，并与外部工具核对既有操作，再恢复执行队列。

参考：SQLite外键约束 https://www.sqlite.org/foreignkeys.html 。事务行为 https://www.sqlite.org/lang_transaction.html 。一致性快照 https://www.sqlite.org/backup.html 。建表约束 https://www.sqlite.org/lang_createtable.html 。

## 18 数据层验收与实施待决策

| 用例 | 操作 | 判定条件 |
|---|---|---|
| DB-01 初始化 | 执行建表脚本并核对表数和外键配置 | 19张业务表，结构检查通过。本轮已复核 |
| DB-02 唯一和时间约束 | 插入重复步骤键、反向区间与未知精度的精确时刻 | 数据库拒绝，本轮使用内存样例复核 |
| DB-03 事务回滚 | 消费确认后模拟登记步骤失败 | 确认、执行和业务数据均回到提交前，由集成测试验证 |
| DB-04 所属用户 | 新增跨用户附件引用或查询其他人的产物 | 服务拒绝且无有效写入，需集成测试 |
| DB-05 故障恢复 | 模拟外部操作未知及旧租约回填 | 不重复执行，旧租约无写入权限，需集成测试 |
| DB-06 快照恢复 | 恢复一致性快照并抽样比对附件 | 记录数、外键与摘要一致，记录实际耗时，需恢复演练 |

实施前需确认资料来源授权、备份保留周期、真实附件规模和试点并发量。由后续集成测试确认状态转换、重试的安全性与MiniClaw数据隔离。
