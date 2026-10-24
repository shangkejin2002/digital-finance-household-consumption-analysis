# Digital Financial Inclusion and Household Food Consumption in China
# Portfolio analysis: thesis specification, data-quality checks, and figures

suppressPackageStartupMessages({
  library(tidyverse)
  library(fixest)
  library(readxl)
  library(modelsummary)
})

# 1. Input and output ---------------------------------------------------------

# Set ANALYSIS_DATA when the authorized file is stored elsewhere, for example:
# Sys.setenv(ANALYSIS_DATA = "/path/to/analysis_data.xlsx")
input_file <- Sys.getenv("ANALYSIS_DATA", unset = "data/analysis_data.xlsx")
figure_dir <- Sys.getenv("FIGURE_DIR", unset = "results/figures")

if (!file.exists(input_file)) {
  stop(
    paste0(
      "分析データが見つかりません: ", input_file, "\n",
      "ANALYSIS_DATA に利用許可を得た分析ファイルのパスを指定してください。"
    )
  )
}

dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

df <- read_excel(input_file, sheet = "Sheet1")

required_columns <- c(
  "ID", "Province", "Engel_2014", "Engel_2018", "DFI"
)
missing_columns <- setdiff(required_columns, names(df))

if (length(missing_columns) > 0) {
  stop(
    paste0(
      "必要な変数が不足しています: ",
      paste(missing_columns, collapse = ", ")
    )
  )
}

if (anyDuplicated(df$ID) > 0) {
  stop("最終分析データの ID が一意ではありません。世帯対応を確認してください。")
}

# Treat_p is reconstructed here rather than read from the Excel column.
# This matches the code used for the thesis robustness model.
median_dfi <- median(df$DFI, na.rm = TRUE)

df <- df %>%
  mutate(
    Treat_p = if_else(DFI >= median_dfi, 1L, 0L)
  )

to_long <- function(data) {
  data %>%
    pivot_longer(
      cols = c(Engel_2014, Engel_2018),
      names_to = "Engel_year",
      values_to = "Engel"
    ) %>%
    mutate(
      Year = if_else(Engel_year == "Engel_2014", 2014L, 2018L),
      Post = if_else(Year == 2018L, 1L, 0L)
    )
}

data_long <- to_long(df)

# 2. Data-quality audit -------------------------------------------------------

quality_summary <- tibble(
  item = c(
    "Households",
    "Province-level regions",
    "DFI median used for Treat_p",
    "Missing Engel values in 2014",
    "Missing Engel values in 2018",
    "Engel values outside [0, 1] in 2014",
    "Engel values outside [0, 1] in 2018"
  ),
  value = c(
    nrow(df),
    n_distinct(df$Province),
    median_dfi,
    sum(is.na(df$Engel_2014)),
    sum(is.na(df$Engel_2018)),
    sum(!is.na(df$Engel_2014) & !between(df$Engel_2014, 0, 1)),
    sum(!is.na(df$Engel_2018) & !between(df$Engel_2018, 0, 1))
  )
)

cat("\nData-quality audit\n")
print(quality_summary, n = Inf)

# 3. Thesis specification ----------------------------------------------------

# These models reproduce the specification and sample used in the thesis.
# The estimates should be interpreted as differences in changes associated
# with baseline DFI, not as definitive causal effects.
did_main_thesis <- feols(
  Engel ~ DFI * Post | ID + Year,
  data = data_long,
  cluster = "Province"
)

did_binary_thesis <- feols(
  Engel ~ Treat_p * Post | ID + Year,
  data = data_long,
  cluster = "Province"
)

cat("\nThesis specification\n")
modelsummary(
  list(
    "Continuous DFI" = did_main_thesis,
    "High vs low DFI" = did_binary_thesis
  ),
  coef_map = c(
    "DFI:Post" = "DFI × 2018",
    "Treat_p:Post" = "High DFI × 2018"
  ),
  fmt = "%.5f",
  output = "markdown"
)

# 4. Sensitivity analysis ----------------------------------------------------

# Engel is a share of food expenditure in total consumption expenditure.
# Because values outside [0, 1] require additional source-data validation,
# this sensitivity analysis retains only households whose values are within
# the theoretical range in both years. It is reported separately and does not
# replace the thesis estimates.
df_valid <- df %>%
  filter(
    between(Engel_2014, 0, 1),
    between(Engel_2018, 0, 1)
  )

data_long_valid <- to_long(df_valid)

did_main_valid <- feols(
  Engel ~ DFI * Post | ID + Year,
  data = data_long_valid,
  cluster = "Province"
)

did_binary_valid <- feols(
  Engel ~ Treat_p * Post | ID + Year,
  data = data_long_valid,
  cluster = "Province"
)

cat("\nSensitivity analysis: households within 0 <= Engel <= 1 in both years\n")
cat("Households:", nrow(df_valid), "\n")
modelsummary(
  list(
    "Continuous DFI" = did_main_valid,
    "High vs low DFI" = did_binary_valid
  ),
  coef_map = c(
    "DFI:Post" = "DFI × 2018",
    "Treat_p:Post" = "High DFI × 2018"
  ),
  fmt = "%.5f",
  output = "markdown"
)

# 5. Figure 1: descriptive changes by DFI group ------------------------------

group_summary <- data_long_valid %>%
  mutate(
    DFI_group = factor(
      Treat_p,
      levels = c(0, 1),
      labels = c("低DFI地域", "高DFI地域")
    )
  ) %>%
  group_by(DFI_group, Year) %>%
  summarise(
    households = n(),
    mean_engel = mean(Engel),
    se = sd(Engel) / sqrt(households),
    lower = mean_engel - 1.96 * se,
    upper = mean_engel + 1.96 * se,
    .groups = "drop"
  )

p_change <- ggplot(
  group_summary,
  aes(x = factor(Year), y = mean_engel, color = DFI_group, group = DFI_group)
) +
  geom_errorbar(aes(ymin = lower, ymax = upper), width = 0.06, linewidth = 0.7) +
  geom_line(linewidth = 1.1) +
  geom_point(size = 3) +
  scale_color_manual(values = c("低DFI地域" = "#4C78A8", "高DFI地域" = "#E45756")) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1)) +
  labs(
    title = "DFI水準別にみた平均エンゲル係数の変化",
    subtitle = "両年とも0〜1の範囲にある世帯を使用（エラーバーは95%信頼区間）",
    x = "調査年",
    y = "平均エンゲル係数",
    color = "2014年のDFI水準",
    caption = "出所：CFPS 2014・2018、PKU-DFIIC 2014。記述統計であり、因果効果を示すものではない。"
  ) +
  theme_minimal(base_size = 13, base_family = "Hiragino Sans") +
  theme(
    legend.position = "top",
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    plot.caption = element_text(hjust = 0, color = "grey35")
  )

ggsave(
  filename = file.path(figure_dir, "engel_change_by_dfi_group.png"),
  plot = p_change,
  width = 8,
  height = 5,
  dpi = 300,
  bg = "white"
)

# 6. Figure 2: thesis estimates and sensitivity analysis ---------------------

extract_effect <- function(model, term, scale_factor, model_label, sample_label) {
  estimate <- unname(coef(model)[term]) * scale_factor * 100
  interval <- as.numeric(
    confint(model, parm = term, level = 0.95)
  ) * scale_factor * 100

  tibble(
    model = model_label,
    sample = sample_label,
    estimate = estimate,
    lower = interval[[1]],
    upper = interval[[2]]
  )
}

effect_data <- bind_rows(
  extract_effect(
    did_main_thesis, "DFI:Post", 10,
    "DFIが10ポイント高い地域", "原論文仕様"
  ),
  extract_effect(
    did_main_valid, "DFI:Post", 10,
    "DFIが10ポイント高い地域", "範囲確認後"
  ),
  extract_effect(
    did_binary_thesis, "Treat_p:Post", 1,
    "高DFI地域と低DFI地域の差", "原論文仕様"
  ),
  extract_effect(
    did_binary_valid, "Treat_p:Post", 1,
    "高DFI地域と低DFI地域の差", "範囲確認後"
  )
) %>%
  mutate(
    sample = factor(sample, levels = c("原論文仕様", "範囲確認後")),
    model = factor(
      model,
      levels = c("高DFI地域と低DFI地域の差", "DFIが10ポイント高い地域")
    )
  )

p_sensitivity <- ggplot(
  effect_data,
  aes(x = estimate, y = model, color = sample)
) +
  geom_vline(xintercept = 0, color = "grey55", linetype = "dashed") +
  geom_errorbarh(
    aes(xmin = lower, xmax = upper),
    height = 0.16,
    position = position_dodge(width = 0.45),
    linewidth = 0.8
  ) +
  geom_point(position = position_dodge(width = 0.45), size = 3) +
  scale_color_manual(values = c("原論文仕様" = "#E45756", "範囲確認後" = "#4C78A8")) +
  labs(
    title = "推定結果とデータ範囲の確認",
    subtitle = "点は推定値、線は95%信頼区間",
    x = "2014年から2018年の相対的な変化（パーセントポイント）",
    y = NULL,
    color = "使用データ",
    caption = "範囲確認後：両年のエンゲル係数が0〜1の世帯。結果は処理方法に敏感である。"
  ) +
  theme_minimal(base_size = 13, base_family = "Hiragino Sans") +
  theme(
    legend.position = "top",
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    plot.caption = element_text(hjust = 0, color = "grey35")
  )

ggsave(
  filename = file.path(figure_dir, "model_sensitivity.png"),
  plot = p_sensitivity,
  width = 8,
  height = 5,
  dpi = 300,
  bg = "white"
)

cat("\nFigures saved to:", normalizePath(figure_dir), "\n")
