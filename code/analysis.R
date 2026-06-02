# Digital Financial Inclusion and Food Consumption in China
# DID analysis and visualization using R

# 1. パッケージの読み込み ---------------------------------------------------

library(tidyverse)
library(fixest)
library(readxl)
library(modelsummary)

# 2. データの読み込み -------------------------------------------------------

# 注意：
# 元データは利用制限があるため、このリポジトリには含めていません。
# 分析を再現する場合は、データファイルを data/ フォルダに配置してください。
#
# 想定するデータファイル名：
# data/analysis_data.xlsx
#
# 使用するシート：
# Sheet1

df <- read_excel("data/analysis_data.xlsx", sheet = "Sheet1")

# データの列名を確認
names(df)


# 3. データ整形 -------------------------------------------------------------

# Engel_2014 と Engel_2018 をロング形式に変換し、
# 年ダミー Year と政策後ダミー Post を作成する。

data_long <- df %>%
  pivot_longer(
    cols = c(Engel_2014, Engel_2018),
    names_to  = "Engel_year",
    values_to = "Engel"
  ) %>%
  mutate(
    Year = if_else(Engel_year == "Engel_2014", 2014L, 2018L),
    Post = if_else(Year == 2018L, 1, 0)
  )

# データの概要を確認
summary(data_long)
datasummary_skim(data_long)


# 4. 主推定：連続 DFI を用いた DID 推定 -----------------------------------

# DID モデル：
# Engel ~ DFI * Post | ID + Year
#
# Engel：エンゲル係数
# DFI：2014年時点の省別デジタル金融包摂指数
# Post：政策後ダミー（2018年 = 1, 2014年 = 0）
# ID + Year：世帯固定効果および年次固定効果
# cluster = "Province"：省レベルでクラスタリングした標準誤差

did_main <- feols(
  Engel ~ DFI * Post | ID + Year,
  data    = data_long,
  cluster = "Province"
)

summary(did_main)

# 回帰結果を表として表示
modelsummary(did_main, fmt = "%.5f")


# 5. 頑健性検証：DFI を二値化した DID 推定 --------------------------------

# Treat_p は元データに含まれている二値変数を使用する。
# Treat_p = 1：高 DFI 地域
# Treat_p = 0：低 DFI 地域

table(data_long$Treat_p)

did_binary <- feols(
  Engel ~ Treat_p * Post | ID + Year,
  data    = data_long,
  cluster = "Province"
)

summary(did_binary)

# 回帰結果を表として表示
modelsummary(did_binary, fmt = "%.5f")


# 6. 可視化 1：DFI 区間別の平均エンゲル係数 -------------------------------

# DFI を 5 ポイント幅で区間化し、
# 2014年・2018年それぞれの平均エンゲル係数を可視化する。

bin_width <- 5

plot_data_year <- data_long %>%
  mutate(
    DFI_bin = floor(DFI / bin_width) * bin_width
  ) %>%
  group_by(Year, DFI_bin) %>%
  summarise(
    mean_Engel = mean(Engel, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(Year, DFI_bin)

p_year <- ggplot(
  plot_data_year,
  aes(
    x = DFI_bin,
    y = mean_Engel,
    color = factor(Year),
    group = factor(Year)
  )
) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2) +
  labs(
    title = "Engel Coefficient by DFI Bins",
    x = "DFI (binned, width = 5)",
    y = "Average Engel Coefficient",
    color = "Year"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "top",
    plot.title = element_text(hjust = 0.5, face = "bold")
  )

print(p_year)


# 7. 可視化 2：高 DFI 地域と低 DFI 地域の比較 ------------------------------

# Treat_p ごとに、DFI 区間別の平均エンゲル係数を可視化する。

plot_data_treat <- data_long %>%
  mutate(
    DFI_bin = floor(DFI / bin_width) * bin_width
  ) %>%
  group_by(Treat_p, DFI_bin) %>%
  summarise(
    mean_Engel = mean(Engel, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(Treat_p, DFI_bin)

p_treat <- ggplot(
  plot_data_treat,
  aes(
    x = DFI_bin,
    y = mean_Engel,
    color = factor(Treat_p),
    group = factor(Treat_p)
  )
) +
  geom_line(linewidth = 1.2) +
  geom_point(size = 2) +
  labs(
    title = "Engel Coefficient by DFI Bins: High vs Low DFI Regions",
    x = "DFI (binned, width = 5)",
    y = "Average Engel Coefficient",
    color = "Treat_p\n0 = Low DFI, 1 = High DFI"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "top",
    plot.title = element_text(hjust = 0.5, face = "bold")
  )

print(p_treat)


# 8. 可視化 3：連続 DFI モデルと二値化モデルの比較 -------------------------

# 連続 DFI を用いた傾向と、
# DFI を二値化した場合の傾向を比較する。

df_long_clean <- data_long %>%
  mutate(
    DFI_bin = floor(DFI / bin_width) * bin_width
  )

# 連続 DFI モデルに対応する可視化データ
# ここでは政策後である 2018 年の平均エンゲル係数を使用する。

plot_main <- df_long_clean %>%
  filter(Post == 1) %>%
  group_by(DFI_bin) %>%
  summarise(
    main_mean = mean(Engel, na.rm = TRUE),
    .groups = "drop"
  )

# 二値化モデルに対応する可視化データ
# ここでは高 DFI 地域 Treat_p == 1 の平均エンゲル係数を使用する。

plot_binary <- df_long_clean %>%
  filter(Treat_p == 1) %>%
  group_by(DFI_bin) %>%
  summarise(
    binary_mean = mean(Engel, na.rm = TRUE),
    .groups = "drop"
  )

plot_merge <- left_join(plot_main, plot_binary, by = "DFI_bin")

p_compare <- ggplot() +
  geom_line(
    data = plot_merge,
    aes(x = DFI_bin, y = main_mean, color = "Continuous DFI"),
    linewidth = 1.2
  ) +
  geom_point(
    data = plot_merge,
    aes(x = DFI_bin, y = main_mean, color = "Continuous DFI"),
    size = 2
  ) +
  geom_line(
    data = plot_merge,
    aes(x = DFI_bin, y = binary_mean, color = "Binary Treat_p"),
    linewidth = 1.2,
    linetype = "dashed"
  ) +
  geom_point(
    data = plot_merge,
    aes(x = DFI_bin, y = binary_mean, color = "Binary Treat_p"),
    size = 2
  ) +
  labs(
    title = "Comparison of DID Patterns: Continuous DFI vs Binary Treat_p",
    x = "DFI (binned, width = 5)",
    y = "Average Engel Coefficient",
    color = "Model Type"
  ) +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "top",
    plot.title = element_text(hjust = 0.5, face = "bold")
  )

print(p_compare)


# 9. 変数の型を確認 ---------------------------------------------------------

sapply(data_long, class)
