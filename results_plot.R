library(ggplot2)
library(ggpubr)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(zeallot)

setwd(dir = "results")
pdf("Rplots.pdf", height = 7, width = 8.5)

# Receives a grouped dataframe, asserts that all groups are equally sized
# then returns the group size, or quits
equal_group_size <- function(df) {
    tmp <- df %>%
        summarise(n = n(), .groups = "drop") %>%
        ungroup()
    min_size <- min(tmp$n)
    max_size <- max(tmp$n)
    stopifnot(min_size == max_size)
    min_size
}

# State of implementation and OQS relevance
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

# OQS reference data
df_oqs <- read.csv("../supercop_liboqs.csv") %>%
    mutate(
        highlight = ifelse(algorithm %in% active_algos, "Implemented", "Other"),
        order = ifelse(algorithm %in% active_algos, 0, 1),
        inter = reorder(paste0(op, " (", highlight, ")"), order),
        algo = reorder(algorithm, order)
    ) %>%
    pivot_longer(
        c(X25..ms.per.op, X50..ms.per.op, X75..ms.per.op),
        names_to = NULL,
        values_to = "perf"
    ) %>%
    select(perf, algo, inter)

# Benchmark data
data_bench <- read.csv("structured/benchmarks.csv")
data_bench <- data_bench %>%
    mutate(
        perf = 10^-3 * time.iter
    )

# Runs data
data_runs <- read.csv("structured/runs.csv")
max_handshakes <- max(data_runs$handshakes)
data_runs <- data_runs %>%
    select(-c(handshakes)) %>%
    pivot_longer(
        c(padding.size:auth.size),
        names_to = "field",
        values_to = "size"
    ) %>%
    mutate(
        transport = ifelse(run.config == "", protocol, paste0(protocol, " (", run.config, ")")), # e.g. drivel (x25519)
        field = sub("\\.size", "", field),
        field = factor(field, levels = c(
            "KEM.public.key", "KEM.ciphertext", "OKEM.ciphertext", "auth", "padding", "mark", "mac"
        )),
        container = factor(container, levels = c("client", "bridge"))
    ) %>%
    select(-c(protocol, run.config)) %>%
    # Assert that all replicas agree on all field sizes
    group_by(transport, container, field) %>%
    summarise(
        size_range = max(size) - min(size),
        size = min(size), .groups = "drop"
    )
stopifnot(all(data_runs$size_range == 0))
data_runs <- data_runs %>%
    select(-c(size_range)) %>%
    # filter such that client only shows fields that they also _send_ and similar for bridge
    filter(
        (container == "client" & (field == "KEM.public.key" | field == "OKEM.ciphertext")) |
            (container == "bridge" & (field == "KEM.ciphertext" | field == "auth")) |
            (field %in% c("padding", "mark", "mac"))
    ) %>%
    filter(size > 0)


# Traffic data
data_traffic <- read.csv("structured/traffic.csv") %>%
    mutate(
        packet_type = paste0(type, " (", peer, ")"), # data (bridge)
        transport = ifelse(run.config == "", protocol, paste0(protocol, " (", run.config, ")")) # e.g. drivel (x25519)
    ) %>%
    mutate(
        transport = as.factor(transport),
        packet_type = as.factor(packet_type),
        direction = as.factor(direction),
        replicate = as.factor(replicate),
    ) %>%
    group_by(transport, replicate) %>%
    mutate(
        timestamp = timestamp - min(timestamp), # time from first packet
    ) %>%
    select(-c(protocol, run.config, type, peer)) %>%
    ungroup()

# ---------- BENCHMARK DATA ----------

data_preexist <- data_bench %>%
    group_by(benchmark) %>%
    filter(any(branch == "main") & any(branch == "obfs4-bench"))

n <- data_preexist %>%
    group_by(benchmark, branch) %>%
    equal_group_size()

# Shows all benchmarks present in both branches
# Filter only where both branches have a benchmark
data_preexist %>%
    ggplot(aes(y = perf, x = branch, fill = branch)) +
    ggtitle(paste0("Running Time Changes in Preexisting Benchmarks (n=", n, ")")) +
    xlab("Branch") +
    ylab("Running time [ms/op]") +
    geom_boxplot(notch = TRUE) +
    facet_wrap(~benchmark, scale = "free")

data_preexist %>%
    ggplot(aes(y = bytes.alloc, x = branch, fill = branch)) +
    ggtitle(paste0("Memory Usage Changes in Preexisting Benchmarks (n=", n, ")")) +
    xlab("Branch") +
    ylab("Bytes allocated [B/op]") +
    geom_boxplot(notch = TRUE) +
    facet_wrap(~benchmark, scale = "free")

# Shows handshake performance with branches colored
# Filter only where benchmarks are "...Handshake"
data_handshake <- data_bench %>%
    filter(
        grepl("transports/drivel", benchmark) |
            grepl("transports/obfs4", benchmark)
    ) %>%
    filter(grepl("Handshake$", benchmark))

n <- data_handshake %>%
    group_by(benchmark, branch) %>%
    equal_group_size()

data_handshake %>%
    ggplot(aes(y = perf, x = benchmark, fill = branch)) +
    ggtitle(paste0("Simulated Handshake Running Time (n=", n, ")")) +
    xlab("Benchmark name") +
    ylab("Running time [ms/op]") +
    geom_boxplot(notch = TRUE)
data_handshake %>%
    ggplot(aes(y = bytes.alloc, x = benchmark, fill = branch)) +
    ggtitle(paste0("Handshake Memory Usage (n=", n, ")")) +
    xlab("Benchmark name") +
    ylab("Bytes allocated [B/op]") +
    geom_boxplot(notch = TRUE)

# Shows KEM benchmarks in main branch
# Filter only where benchmarks are "BenchmarkKems" or "BenchmarkOkems"
data_kems <- data_bench %>%
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
        inter = reorder(paste0(op, " (", highlight, ")"), order),
        algo = reorder(algo, order)
    )

n <- data_kems %>%
    group_by(algo, inter) %>%
    equal_group_size()

data_kems %>%
    ggplot(aes(y = perf, x = algo, fill = inter)) +
    scale_fill_manual(
        values = c(
            "#F8766D", "#00BA38", "#619CFF",
            "lightgrey", "grey", "darkgrey"
        ),
    ) +
    ggtitle(paste0("(O)KEM Running Time (n=", n, ")")) +
    labs(fill = "Operation (availability)") +
    xlab("Benchmark name") +
    ylab("log Running time [ms/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_y_continuous(trans = "log10") +
    geom_col(position = "dodge", width = 1) # +
# stat_summary(
#     data = df_oqs,
#     aes(y = perf, x = algo, fill = inter),
#     fun = median, fun.min = min, fun.max = max,
#     inherit.aes = FALSE, colour = "black", size = 0.3,
#     position = position_dodge(width = 1)
# )
# TODO eventually find a way to tell this story :D
data_kems %>%
    ggplot(aes(y = bytes.alloc, x = algo, fill = inter)) +
    scale_fill_manual(
        values = c(
            "#F8766D", "#00BA38", "#619CFF",
            "lightgrey", "grey", "darkgrey"
        ),
    ) +
    ggtitle(paste0("(O)KEM Memory Usage (n=", n, ")")) +
    labs(fill = "Operation (availability)") +
    xlab("Benchmark name") +
    ylab("log Bytes allocated [B/op]") +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_y_continuous(trans = "log10") +
    geom_col(position = "dodge")

# ---------- TRAFFIC DATA ----------
transform_traffic <- function(data, size_column, granularity) {
    df <- data %>%
        # Bin data in 100ms regions, keep all other columns
        mutate(
            time_bin = round(timestamp, granularity)
        ) %>%
        group_by(.data$transport, .data$packet_type, .data$direction, .data$replicate, .data$time_bin) %>%
        summarise(bitrate = sum({{ size_column }}) / 10^-granularity / 1000, .groups = "drop")

    n <- df %>%
        group_by(.data$transport, .data$packet_type, .data$direction, .data$replicate) %>%
        summarise(n = n(), .groups = "drop") %>%
        group_by(.data$transport, .data$packet_type, .data$direction) %>%
        equal_group_size()

    # Average traffic over replicates, ensure all replicas have values (even 0) at all time_bins
    df <- df %>%
        group_by(.data$time_bin) %>%
        complete(.data$transport, .data$packet_type, .data$direction, .data$replicate, fill = list(bitrate = 0)) %>%
        group_by(.data$transport, .data$packet_type, .data$direction, .data$time_bin) %>%
        summarise(bitrate = mean(.data$bitrate), .groups = "drop") %>%
        # Remove direction column, but negate traffic with downstream flow (2 columns for bitrate)
        mutate(
            bitrate = ifelse(.data$direction == "upstream", .data$bitrate, -.data$bitrate)
        ) %>%
        select(-"direction")

    list(n, df)
}

# Shows traffic over entire test with peers and type colored
c(n, data_traffic_overview) %<-% (
    data_traffic %>%
        transform_traffic(TCP.payload.size, 2 - max_handshakes)
)

data_traffic_overview %>%
    ggplot(aes(y = bitrate, x = time_bin, fill = packet_type)) +
    ggtitle(paste0("Network Traffic over Time (TCP payloads, n=", n, ")")) +
    labs(fill = "Packet type (peer)") +
    xlab("Time since client Tor startup [s]") +
    ylab("Network traffic [kbps]") +
    scale_x_continuous(n.breaks = 10) +
    geom_col() +
    facet_wrap(~transport, ncol = 1)


# Shows traffic in handshake only but more detailed
c(n, data_traffic_handshake) %<-% (
    data_traffic %>%
        filter(grepl("handshake", packet_type)) %>%
        transform_traffic(key.exchange.size, 4 - max_handshakes)
)

data_traffic_handshake_totals <- data_traffic %>%
    filter(grepl("handshake", packet_type)) %>%
    group_by(transport, direction, replicate) %>%
    summarise(total = sum(key.exchange.size), .groups = "drop") %>%
    group_by(transport, direction) %>%
    summarise(total = mean(total), .groups = "drop") %>%
    mutate(
        total = ifelse(direction == "upstream", total, -total),
    )

p1 <- data_traffic_handshake %>%
    ggplot(aes(y = bitrate, x = time_bin * 1000)) +
    ggtitle(paste0("Traffic for Key Exchange (TCP payloads, n=", n, ")")) +
    xlab("Time since client Tor startup [ms]") +
    ylab("Network traffic [kbps]") +
    scale_x_continuous(n.breaks = 10) +
    geom_col() +
    facet_wrap(~transport, ncol = 1)
p2 <- data_traffic_handshake_totals %>%
    ggplot(aes(y = total, x = 0)) +
    ggtitle("Total bytes") +
    theme(
        axis.title.x = element_blank(),
        axis.text.x = element_blank(),
        axis.ticks.x = element_blank(),
        axis.title.y = element_blank(),
    ) +
    geom_col() +
    geom_text(aes(y = total, label = paste(total, "B"), vjust = ifelse(total > 0, 2, -1)), color = "white") +
    facet_wrap(~transport, ncol = 1)

ggarrange(p1, p2,
    nrow = 1, align = "h",
    widths = c(4, 1),
    common.legend = TRUE
)

# Shows frequency distribution of TCP payload sizes
data_traffic %>%
    mutate(
        TCP.packet.size = ifelse(packet_type == "data", TCP.payload.size + 32, TCP.payload.size + 40)
    ) %>%
    ggplot(aes(x = TCP.packet.size, fill = packet_type)) +
    ggtitle("Distribution of TCP Packet Sizes") +
    labs(fill = "Packet type (peer)") +
    xlab("log TCP packet size [B]") +
    ylab("Frequency [% of packets]") +
    scale_y_continuous(labels = scales::percent) +
    scale_x_log10() +
    expand_limits(x = 10) +
    geom_histogram(aes(y = after_stat(count / sum(count))), binwidth = 0.1) +
    facet_wrap(~transport, ncol = 1)

# Shows handshake packet contents by size (uses runs.csv, per transport and container - rest labels)
data_runs %>%
    ggplot(aes(x = container, y = size, fill = field)) +
    ggtitle("Composition of Handshake Packets") +
    xlab("Packet origin") +
    ylab("Field size [B]") +
    scale_y_continuous(breaks = function(z) seq(0, range(z)[2], by = 32)) +
    geom_col() +
    geom_text(aes(label = field), position = position_stack(vjust = 0.5)) +
    facet_wrap(~transport, nrow = 1)

warnings()
