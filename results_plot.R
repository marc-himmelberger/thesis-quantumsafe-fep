library(ggplot2)
library(dplyr, warn.conflicts = FALSE)

setwd(dir = "results")

# Benchmark data
data_bench <- read.csv("structured/benchmarks.csv")
data_bench <- data_bench %>%
    mutate(
        perf = 10^9 / time.iter
    )

# Shows all benchmarks present in both branches
# Filter only where both branches have a benchmark
data_bench %>%
    group_by(benchmark) %>%
    filter(any(branch == "main") & any(branch == "obfs4-bench")) %>%
    ggplot(aes(y = perf, x = benchmark, fill = branch)) +
    ggtitle("Performance Changes in Preexisting Benchmarks") +
    xlab("benchmark name") +
    ylab("log performance [op/s]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_y_continuous(trans = "log10") +
    geom_bar(position = "dodge", stat = "identity")
data_bench %>%
    group_by(benchmark) %>%
    filter(any(branch == "main") & any(branch == "obfs4-bench")) %>%
    ggplot(aes(y = bytes.alloc, x = benchmark, fill = branch)) +
    ggtitle("Memory Usage Changes in Preexisting Benchmarks") +
    xlab("benchmark name") +
    ylab("log bytes allocated [B/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_y_continuous(trans = "log10") +
    geom_bar(position = "dodge", stat = "identity")

# Shows handshake performance with branches colored
# Filter only where benchmarks are "...Handshake"
data_bench %>%
    group_by(benchmark) %>%
    filter(grepl("Handshake$", benchmark)) %>%
    ggplot(aes(y = perf, x = benchmark, fill = branch)) +
    ggtitle("Handshake Performance") +
    xlab("benchmark name") +
    ylab("performance [op/s]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    geom_bar(position = "dodge", stat = "identity")
data_bench %>%
    group_by(benchmark) %>%
    filter(grepl("Handshake$", benchmark)) %>%
    ggplot(aes(y = bytes.alloc, x = benchmark, fill = branch)) +
    ggtitle("Handshake Memory Usage") +
    xlab("benchmark name") +
    ylab("bytes allocated [B/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    geom_bar(position = "dodge", stat = "identity")

# Shows KEM benchmarks in main branch
# Filter only where benchmarks are "BenchmarkKems" or "BenchmarkOkems"
active_algos <- c("x25519", "EtE-x25519")
relevant_algos <- c(
    "ML-KEM-512",
    "ML-KEM-768",
    "ML-KEM-1024",
    "FrodoKEM-640-AES",
    "FrodoKEM-640-SHAKE",
    "FrodoKEM-976-AES",
    "FrodoKEM-976-SHAKE",
    "FrodoKEM-1344-AES",
    "FrodoKEM-1344-SHAKE",
    "HQC-128",
    "HQC-192",
    "HQC-256",
    "Classic-McEliece-348864",
    "Classic-McEliece-348864f",
    "Classic-McEliece-460896",
    "Classic-McEliece-460896f",
    "Classic-McEliece-6688128",
    "Classic-McEliece-6688128f",
    "Classic-McEliece-6960119",
    "Classic-McEliece-6960119f",
    "Classic-McEliece-8192128",
    "Classic-McEliece-8192128f"
)
data_bench %>%
    filter(
        grepl("BenchmarkKems$", benchmark) |
            grepl("BenchmarkOkems$", benchmark)
    ) %>%
    mutate(
        op = sub(".*-", "", subbench),
        algo = sub("-[^-]+$", "", subbench)
    ) %>%
    filter(
        algo %in% relevant_algos | algo %in% active_algos
    ) %>%
    mutate(
        highlight = ifelse(algo %in% active_algos, "Implemented", "Other"),
        order = ifelse(algo %in% active_algos, 0, 1),
        inter = reorder(paste0(op, " (", highlight, ")"), order)
    ) %>%
    ggplot(aes(y = perf, x = reorder(algo, order), fill = inter)) +
    scale_fill_manual(
        values = c(
            "#F8766D", "#00BA38", "#619CFF",
            "lightgrey", "grey", "darkgrey"
        ),
    ) +
    ggtitle("(O)KEM Performance") +
    labs(fill = "Operation (availability)") +
    xlab("benchmark name") +
    ylab("log performance [op/s]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_y_continuous(trans = "log10") +
    geom_bar(position = "dodge", stat = "identity")
data_bench %>%
    filter(
        grepl("BenchmarkKems$", benchmark) |
            grepl("BenchmarkOkems$", benchmark)
    ) %>%
    mutate(
        op = sub(".*-", "", subbench),
        algo = sub("-[^-]+$", "", subbench)
    ) %>%
    filter(
        algo %in% relevant_algos | algo %in% active_algos
    ) %>%
    mutate(
        highlight = ifelse(algo %in% active_algos, "Implemented", "Other"),
        order = ifelse(algo %in% active_algos, 0, 1),
        inter = reorder(paste0(op, " (", highlight, ")"), order)
    ) %>%
    ggplot(aes(y = bytes.alloc, x = reorder(algo, order), fill = inter)) +
    scale_fill_manual(
        values = c(
            "#F8766D", "#00BA38", "#619CFF",
            "lightgrey", "grey", "darkgrey"
        ),
    ) +
    ggtitle("(O)KEM Memory Usage") +
    labs(fill = "Operation (availability)") +
    xlab("benchmark name") +
    ylab("log bytes allocated [B/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_y_continuous(trans = "log10") +
    geom_bar(position = "dodge", stat = "identity")

warnings()
