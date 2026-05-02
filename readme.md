<b>[survivor_mvp_fix](/survivor_mvp)</b>: Display survivors' data such as killing SI, CI, FF done to teammates
（生还者 MVP 数据显示，可显示生还者击杀特感、丧尸、友伤等数据）

<ul><b>漏洞修复</b>:
<li>避免百分比计算除零导致崩溃风险，添加 if (total > 0) 保护，否则设为 0；</li>
<li>GetRank 返回值未初始化，int rank = 0，现在 rank 初始化为 0；</li>
<li>roundEndPrint 消息重复/遗漏，错误 break 导致只发第一个玩家，重构为：仅首次调用时生成消息，并发送给所有符合条件的玩家。</li>
</ul>
<ul><b>新增功能</b>：
<li>可设置时间间隔自动播报MVP击杀统计（默认 120 秒）。</li>
</ul>
