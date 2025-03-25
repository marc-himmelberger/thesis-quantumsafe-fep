library(ggplot2)
library(dplyr)

setwd(dir = "results")

# Benchmark data
data_bench <- read.csv("structured/benchmarks.csv")

# Filter only where both branches have a benchmark
data_both <- data_bench %>%
    group_by(benchmark) %>%
    filter(any(branch == "main") & any(branch == "obfs4-bench"))

# Shows all benchmarks present in both branches
ggplot(data_both, aes(fill = branch, y = time.iter, x = benchmark)) +
    ggtitle("Performance Changes in Preexisting Benchmarks") +
    xlab("benchmark name") +
    ylab("time/iter [ns/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    geom_bar(position = "dodge", stat = "identity")

# Filter only where benchmarks are "...Handshake"
data_hs <- data_bench %>%
    group_by(benchmark) %>%
    filter(grepl("Handshake$", benchmark))

# Shows handshake performance with branches colored
ggplot(data_hs, aes(fill = branch, y = time.iter, x = benchmark)) +
    ggtitle("Handshake Performance") +
    xlab("benchmark name") +
    ylab("time/iter [ns/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    geom_bar(position = "dodge", stat = "identity")

# Filter only where benchmarks are "BenchmarkKems" or "BenchmarkOkems"
data_kems <- data_bench %>%
    filter(
        grepl("BenchmarkKems$", benchmark) |
            grepl("BenchmarkOkems$", benchmark)
    ) %>%
    mutate(
        op = sub(".*-", "", subbench),
        algo = sub("-[^-]+$", "", subbench)
    )

# Shows KEM benchmarks in main branch
ggplot(data_kems, aes(fill = op, y = time.iter, x = algo)) +
    ggtitle("(O)KEM Performance") +
    xlab("benchmark name") +
    ylab("time/iter [ns/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    geom_bar(position = "dodge", stat = "identity") +
    scale_y_continuous(trans = "log10")
