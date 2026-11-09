# 免费行情接口速查（东方财富，实测可用）

非官方接口，无文档、无 SLA、字段可能随时变。以下字段含义与单位都是**实测反推**的，
换标的后请先 `curl` 核对一次再写进代码。所有接口都不需要 API key。

四个域名分工：

| 域名 | 用途 |
| --- | --- |
| `push2.eastmoney.com` | 实时快照、个股资金流、板块列表 |
| `push2his.eastmoney.com` | 历史 K 线、分时 |
| `datacenter-web.eastmoney.com` | 数据中心报表：南向资金、十大成交股、持股 |
| `np-anotice-stock` / `np-listapi` | 公告、7x24 快讯 |

---

## 一、南向资金（港股通）

### 1. 日度汇总 —— 新闻里那个"净买入/净卖出多少亿"

```
https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_MUTUAL_DEAL_HISTORY
  &columns=ALL&pageSize=5&sortColumns=TRADE_DATE&sortTypes=-1
  &filter=(MUTUAL_TYPE="002")
```

`MUTUAL_TYPE`：`002` = 港股通(沪)，`004` = 港股通(深)。两个通道要**分别取再相加**，
新闻口径的"南向资金"= 002 + 004。

主要字段：

| 字段 | 含义 | 单位 |
| --- | --- | --- |
| `NET_DEAL_AMT` | 净买入 | 百万元，÷100 = 亿元 |
| `BUY_AMT` / `SELL_AMT` | 买入 / 卖出 | 同上 |
| `DEAL_AMT` | 成交额 | 同上 |
| `LEAD_STOCKS_NAME` | 当日领涨股 | — |
| `LS_CHANGE_RATE` | 领涨股涨幅 | % |
| `INDEX_CLOSE_PRICE` / `INDEX_CHANGE_RATE` | 恒指收盘 / 涨跌 | — / % |
| `HOLD_MARKET_CAP` | 港股通持股总市值 | 元（原始值，不缩比） |

实测（2026-11-05，港股通沪）：净买入 -133.39 亿，买入 361.86 亿，卖出 495.25 亿，成交 857.1 亿。
注意同一行里 `HOLD_MARKET_CAP` 是原始元、金额字段是百万元——**单位不统一是这家的常态**。

> **数据时效：只有盘后才有。** 实测 2026-11-06 14:55（港股盘中），`RPT_MUTUAL_DEAL_HISTORY`、
> `RPT_MUTUAL_TOP10DEAL`、`RPT_MUTUAL_HOLD_DET` 三个报表最新都还停在 11-05。
> 想做盘中实时刷新是没有的，只能收盘后取 T 日结果。

### 2. 十大成交活跃股 —— 谁被买最多、谁被卖最多

```
https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_MUTUAL_TOP10DEAL
  &columns=ALL&pageSize=10&sortColumns=TRADE_DATE,RANK&sortTypes=-1,1
  &filter=(MUTUAL_TYPE="002")
```

| 字段 | 含义 |
| --- | --- |
| `NET_BUY_AMT` | 净买入（元，正=净买入，负=净卖出），**直接可用于排名** |
| `DEAL_AMT` | 成交额（元） |
| `MUTUAL_RATIO` | 占该股当日成交额比例（%），看"南向定价权"最有用 |
| `RANK` | 当日排名 |
| `CHANGE_RATE` / `CLOSE_PRICE` | 涨跌幅 / 收盘价 |

实测（2026-11-05，港股通沪）：腾讯 -19.02 亿、小米 -21.38 亿、盈富基金 -40.85 亿，
十大合计 -102.86 亿 —— 与上面的 -133.39 亿总量能对上，说明口径一致。

排序换成 `sortColumns=NET_BUY_AMT&sortTypes=-1` 就是"净买入排行"，`1` 就是"净卖出排行"。

### 3. 个股被南向持有了多少

```
https://datacenter-web.eastmoney.com/api/data/v1/get?reportName=RPT_MUTUAL_HOLD_DET
  &columns=ALL&pageSize=10&sortColumns=HOLD_DATE&sortTypes=-1
  &filter=(SECURITY_CODE="00700")
```

返回 `HOLD_NUM`（持股数）、`HOLD_SHARES_RATIO`（占已发行股份 %）、`HOLD_MARKET_CAP`（市值，元）。
实测腾讯：4.73 亿股，占 5.2%，市值 2036 亿。

### 4. 拿不到的

- **盘中实时的南向净流入**：`push2/api/qt/kamt/get` 还在返回，但 `dayNetAmtIn` 已经等于
  `dayAmtThreshold`（配额本身），是占位值，不是真实成交。沪深港通 2024 年收紧披露后，
  实时资金流就没有了，只剩盘后日度汇总。
- **北向个股净买入**：同一个 `RPT_MUTUAL_TOP10DEAL` 里 `MUTUAL_TYPE=001/003` 的
  `NET_BUY_AMT` 恒为 `null`，只剩成交额和占比。

---

## 二、行情与技术面

### 实时快照

```
https://push2.eastmoney.com/api/qt/stock/get?secid=116.00700&fields=f43,f44,f45,f46,f47,f48,f57,f58,f60,f116,f117,f167,f168,f169,f170,f171,f59
```

| 字段 | 含义 | 备注 |
| --- | --- | --- |
| `f43` | 最新价 | 需除以 10^`f59` |
| `f59` | 小数位 | 港股通常 3，指数 2 |
| `f60` | 昨收 | 同样要缩放 |
| `f44/f45/f46` | 最高/最低/今开 | |
| `f47/f48` | 成交量(股) / 成交额(元) | |
| `f50` | 量比 | 104 = 1.04 |
| `f116/f117` | 总市值 / 流通市值 | 元 |
| `f167` | 市净率 | 腾讯 2.92 |
| `f168` | 换手率 | % |
| `f169/f170/f171` | 涨跌额 / 涨跌幅 / 振幅 | % |

港股 `f162`（市盈率）返回 0，估值得另找接口。

### 历史 K 线

```
https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=116.00700&klt=101&fqt=1
  &beg=20260101&end=20500101
```

`klt`：101 日 / 102 周 / 103 月 / 1、5、15、30、60 分钟。`fqt`：0 不复权 / 1 前复权 / 2 后复权。
**必须带 `beg`/`end`**，只传 `lmt` 会返回 `rc:102`（无 data）。

### 分时

```
https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid=116.00700&ndays=1
  &fields1=f1,f2,f3,f4,f5,f6,f7,f8&fields2=f51,f52,f53,f54,f55,f56,f57,f58
```

### 个股资金流（主力 / 大单 / 超大单）

```
https://push2.eastmoney.com/api/qt/stock/fflow/kline/get?secid=116.00700&klt=1&lmt=0
  &fields1=f1,f2,f3,f7&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63
```

`klines` 每行是 `时间,主力净流入,小单,中单,大单,超大单`。港股也能返回，但量级/口径没官方说明，
当相对趋势看可以，别当权威数字用。

---

## 三、其他

| 数据 | 接口 |
| --- | --- |
| 港股公告 | `np-anotice-stock.eastmoney.com/api/security/ann?ann_type=H&stock_list=00700&page_size=10` |
| 7x24 快讯 | `np-listapi.eastmoney.com/comm/web/getFastNewsList?client=web&biz=web_724&fastColumn=102&pageSize=20&req_trace=<毫秒时间戳>` |
| 板块/指数列表 | `push2.eastmoney.com/api/qt/clist/get?fs=m:124&fields=f12,f14,f2,f3` |
| 港股通持股排名 | 用 `RPT_MUTUAL_HOLD_DET` 换 `sortColumns=HOLD_MARKET_CAP` 排序 |

`ann_type`：`A` 沪市 / `H` 港股。7x24 快讯必须带 `req_trace`，否则报参数缺失。

---

## 四、成交明细与买卖力量

### 内盘 / 外盘（累计主动买、主动卖）—— 港股 A 股都有

实时快照 `push2/api/qt/stock/get` 里：

| 字段 | 含义 |
| --- | --- |
| `f47` | 成交量（**A 股单位是「手」，港股是「股」**） |
| `f49` | 外盘 = 主动买成交量，单位同 `f47` |
| `f47 - f49` | 内盘 = 主动卖成交量 |

实测校验（2026-11-09 上午，用全天逐笔反算）：

| 标的 | `f47` | `f49` | 逐笔聚合出的主动买 |
| --- | --- | --- | --- |
| 港交所 00388 | 413,804 | 269,969 | 269,563 |
| 电能实业 00006 | 157,286 | 81,733 | 81,233 |
| 贵州茅台 600519 | 8,629 手 | 4,363 手 | 4,363 手（= 腾讯源的外盘） |

两只港股的逐笔总量与 `f47` **完全相等**，主动买与 `f49` 差在 0.15% 以内，
所以 `f49` 就是外盘，可以直接用来算"买多少、卖多少"。

### 逐笔成交（带买卖方向）

```
https://push2.eastmoney.com/api/qt/stock/details/get?secid=116.00700&pos=-3000
  &fields1=f1,f2,f3,f4&fields2=f51,f52,f53,f54,f55
```

每行格式 `时间,价格,成交量,笔数,方向`：

| 位置 | 含义 |
| --- | --- |
| 1 | 时间 `HH:mm:ss` |
| 2 | 成交价 |
| 3 | 成交量（港股是股，A 股是手） |
| 4 | 笔数（A 股有值，港股恒为 0） |
| 5 | 方向：`2` = 主动买（成交在卖价），`1` = 主动卖（成交在买价） |

`pos=-N` 取最近 N 笔，**一次最多 3000 笔**。腾讯这种活跃股 3000 笔只够 30 分钟，
冷门股能覆盖全天——要算当日累计请直接用 `f49`，别聚合逐笔。

### 五档盘口

- **A 股**：走腾讯源 `https://qt.gtimg.cn/q=sh600519`（**GBK 解码**），
  第 9–18 位是买一~买五（价、量交替），第 19–28 位是卖一~卖五。
- **港股**：**免费源拿不到**。腾讯串里买一价 = 最新价、量为 0，卖档全 0；
  港股 L2 盘口是交易所授权数据。
- 东财 `push2` 老文章里那套 `f11`–`f40`（五档买卖）**已经失效**：
  实测请求 f1–f60 只返回 `f43`–`f60` 中的十几个字段，盘口字段一个都不给。

---

## 五、使用注意

1. **单位不统一**：金额可能同时出现"元""百万元""万元"，同一行内也可能混着原始值（市值）。
   每次接新字段都要拿一个已知的数反算一遍。
2. **频率**：单 IP 高频会被限流或临时封。3–5 秒一次完全没问题，别做秒级全市场扫描。
3. **数值可能为空**：停牌、无数据时 `f43` 可能是 `"-"`，取数要兜底。
4. **不是官方承诺**：字段改名、报表下线（比如 `RPT_MUTUAL_STOCK_HOLDDETAILS` 就已经不存在了）
   都可能发生，接口挂了别当成自己代码的 bug。
