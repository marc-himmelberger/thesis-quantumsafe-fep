# For easier editing: sudo rstudio-server start
# --> http://localhost:8787/

library(ggplot2)
library(ggpubr)
library(dplyr, warn.conflicts = FALSE)
library(tidyr)
library(zeallot)
library(ggh4x)
library(ggfittext)

setwd(dir = "~/thesis-quantumsafe-fep/results")
if (!interactive()) {
    # Code for non-interactive sessions (e.g., Rscript)
    cat("This is running via Rscript, outputting to PDF...\n")
    aspect <- c(4, 3)
    scale <- 2.3
    size_in <- aspect * scale
    pdf("Rplots.pdf", width = size_in[1], height = size_in[2])
}

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

#################
#  START CONST  #
#################

# State of implementation and OQS relevance
active_kems <- readr::read_delim(
    "nist_level  ;  algo
       L0      ;  x25519
       L0      ;  FEO-x25519
       L1      ;  FEO-Classic-McEliece-348864
       L3      ;  FEO-Classic-McEliece-460896
       L5      ;  FEO-Classic-McEliece-6688128
       L5      ;  FEO-Classic-McEliece-6960119
       L5      ;  FEO-Classic-McEliece-8192128
       L1      ;  BIKE-L1
       L3      ;  BIKE-L3
       L5      ;  BIKE-L5
       L1      ;  ML-KEM-512
       L3      ;  ML-KEM-768
       L5      ;  ML-KEM-1024
       L1      ;  FEO-ML-KEM-512
       L3      ;  FEO-ML-KEM-768
       L5      ;  FEO-ML-KEM-1024
       L1      ;  FrodoKEM-640-AES
       L3      ;  FrodoKEM-976-AES
       L5      ;  FrodoKEM-1344-AES
       L1      ;  FEO-FrodoKEM-640-AES
       L3      ;  FEO-FrodoKEM-976-AES
       L5      ;  FEO-FrodoKEM-1344-AES
       L1      ;  HQC-128
       L3      ;  HQC-192
       L5      ;  HQC-256
       L1      ;  FEO-HQC-128
       L3      ;  FEO-HQC-192
       L5      ;  FEO-HQC-256",
    trim_ws = TRUE, comment = "#", delim = ";"
)
drivel_parameter_sets <- readr::read_delim(
    "   Name    ;  Combination
    Drivel-L0   ;  x25519|FEO-x25519
    Drivel-L1a  ;  ML-KEM-512|FEO-ML-KEM-512
    Drivel-L1b  ;  BIKE-L1|FEO-ML-KEM-512
    Drivel-L1c  ;  ML-KEM-512|FEO-HQC-128
    Drivel-L1d  ;  ML-KEM-512|FEO-Classic-McEliece-348864
    Drivel-L3a  ;  ML-KEM-768|FEO-ML-KEM-768
    Drivel-L3b  ;  BIKE-L3|FEO-ML-KEM-768
    Drivel-L3c  ;  ML-KEM-768|FEO-HQC-192
    Drivel-L3d  ;  ML-KEM-768|FEO-Classic-McEliece-460896
    Drivel-L5a  ;  ML-KEM-1024|FEO-ML-KEM-1024
    Drivel-L5b  ;  BIKE-L5|FEO-ML-KEM-1024
    Drivel-L5c  ;  ML-KEM-1024|FEO-HQC-256
    Drivel-L5d  ;  ML-KEM-1024|FEO-Classic-McEliece-6688128",
    trim_ws = TRUE, comment = "#", delim = ";"
)

#################
#  START DATA   #
#################

# OQS reference data
df_oqs <- read.csv("../supercop_liboqs.csv") %>%
    rename(algo = algorithm) %>%
    inner_join(
        active_kems,
        by = c("algo" = "algo")
    ) %>%
    mutate(
        order = match(nist_level, c("L0", "L1", "L3", "L5")),
        algo = reorder(algo, order)
    ) %>%
    pivot_longer(
        c(X25..ms.per.op, X50..ms.per.op, X75..ms.per.op),
        names_to = NULL,
        values_to = "perf"
    ) %>%
    select(perf, algo, op)

# Benchmark data
data_bench <- read.csv("structured/benchmarks.csv")
data_bench <- data_bench %>%
    left_join(drivel_parameter_sets, by = c("subbench" = "Combination")) %>%
    rename(protocol_with_level_and_subid_pretty = Name) %>%
    mutate(
        perf = 10^-6 * time.iter, # ns/op to ms/op
        protocol_pretty = ifelse(grepl("transports/obfs4", benchmark),
            "Obfs4",
            ifelse(grepl("transports/drivel", benchmark),
                "Drivel",
                "?"
            )
        ),
        protocol_with_level_pretty = ifelse(grepl("transports/obfs4", benchmark),
            "Obfs4",
            sub("[abcd]$", "", protocol_with_level_and_subid_pretty)
        ),
        subbench_pretty = ifelse(grepl("transports/obfs4", benchmark),
            "x25519ell2",
            gsub("\\|", "\n", subbench)
        )
    ) %>%
    mutate(
        order = match(protocol_with_level_and_subid_pretty, drivel_parameter_sets$Name),
        subbench_pretty = reorder(subbench_pretty, order)
    )

# Runs data
data_runs <- read.csv("structured/runs.csv")
max_handshakes <- 1 # XXX: Hack, see below; max(data_runs$handshakes)
stopifnot(
    2 == (
        data_runs %>% # assert that only one replicate has multiple handshakes
            filter(handshakes > 1) %>%
            nrow()
    )
)
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

# For the one run with 2 handshakes (check using runs.csv):
#   drop data_traffic rows for first handshake ("handshake,bridge" with smaller numbers - one "upstream" one "downstream")
#   for all "data,bridge", reduce timestamp by delta between "handshake,bridge,upstream"
# XXX: I'm lazy, so I just looked up the appropriate rows myself
delta_handshake <- data_traffic[data_traffic$X == 1099, ]$timestamp # timestamp for first packet is "0"
data_traffic <- data_traffic %>%
    filter(
        !X %in% c(1097, 1098)
    ) %>%
    mutate(
        timestamp = ifelse(X >= 1099 & X <= 1358,
            timestamp - delta_handshake,
            timestamp
        )
    ) %>%
    filter(
        timestamp >= 0
    )
rm(delta_handshake)


#################
#  START PLOTS  #
#################

# ---------- BENCHMARK DATA ----------
print("---- data_preexist ----")
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
    labs(fill = "Branch") +
    geom_boxplot(notch = TRUE) +
    facet_wrap(~benchmark, scales = "free")

data_preexist %>%
    ggplot(aes(y = bytes.alloc, x = branch, fill = branch)) +
    ggtitle(paste0("Memory Usage Changes in Preexisting Benchmarks (n=", n, ")")) +
    xlab("Branch") +
    ylab("Bytes allocated [B/op]") +
    labs(fill = "Branch") +
    geom_boxplot(notch = TRUE) +
    facet_wrap(~benchmark, scales = "free")

# Shows handshake performance with branches colored
# Filter only where benchmarks are "...Handshake" for Drivel or Obfs4
# Restrict to drivel_parameter_sets for Drivel
print("---- data_handshake ----")
data_handshake <- data_bench %>%
    filter(
        grepl("transports/drivel", benchmark) |
            grepl("transports/obfs4", benchmark)
    ) %>%
    filter(grepl("Handshake$", benchmark)) %>%
    filter(
        subbench %in% drivel_parameter_sets$Combination |
            grepl("transports/obfs4", benchmark)
    ) %>%
    left_join(
        drivel_parameter_sets,
        by = c("subbench" = "Combination")
    ) %>%
    mutate( # Example: "Drivel-L3b"
        transport_letter = ifelse(grepl("x25519", subbench_pretty), # "b" or "a" for obfs4
            "a", # default letter for L0 and obfs4
            sub("^.*L\\d", "", sub("\\)", "", Name))
        )
    )

n <- data_handshake %>%
    group_by(benchmark, subbench, branch) %>%
    equal_group_size()

data_handshake %>%
    filter(branch == "main") %>%
    group_by(subbench_pretty, protocol_with_level_pretty) %>%
    summarise(sd.perf = sd(perf), sd.bytes.alloc = sd(bytes.alloc), .groups = "drop") %>%
    summarise(max.sd.perf = max(sd.perf), max.sd.bytes.alloc = max(sd.bytes.alloc))

# Keep only main branch and calculate averages per group
data_handshake <- data_handshake %>%
    filter(branch == "main") %>%
    group_by(subbench_pretty, protocol_with_level_pretty) %>%
    summarise(
        perf = mean(perf),
        bytes.alloc = mean(bytes.alloc),
        transport_letter = first(transport_letter),
        .groups = "drop"
    )

data_handshake %>%
    ggplot(aes(y = perf, x = subbench_pretty, color = transport_letter)) +
    ggtitle(paste0("Simulated Handshake Running Time (n=", n, ")")) +
    xlab("Benchmark name") +
    ylab("Running time [ms]") +
    guides(color = "none") + # hides "transport_letter" from legend
    geom_point(size = 2) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    facet_grid(~protocol_with_level_pretty, scales = "free_x", space = "free")
data_handshake %>%
    ggplot(aes(y = bytes.alloc, x = subbench_pretty, color = transport_letter)) +
    ggtitle(paste0("Simulated Handshake Memory Usage (n=", n, ")")) +
    xlab("Benchmark name") +
    ylab("Bytes allocated [B]") +
    guides(color = "none") + # hides "transport_letter" from legend
    geom_point(size = 2) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1)) +
    facet_grid(~protocol_with_level_pretty, scales = "free_x", space = "free")

# Shows KEM benchmarks in main branch
# Filter only where benchmarks are "BenchmarkKems" or "BenchmarkOkems"
# Sort KEMs by strength
print("---- data_kems ----")
data_kems <- data_bench %>%
    filter(
        grepl("BenchmarkKems$", benchmark) |
            grepl("BenchmarkOkems$", benchmark)
    ) %>%
    mutate( # Example: "FEO-HQC-128-KeyGen"
        op = sub(".*-", "", subbench), # "KeyGen"
        algo = sub("-[^-]+$", "", subbench), # "FEO-HQC-128"
        algo_name = sub("-\\d.*", "", algo), # "FEO-HQC", "BIKE-L1"
        algo_name = sub("-L\\d.*", "", algo_name), # "FEO-HQC", "BIKE"
        base_kem = sub("^FEO-", "", algo_name), # "HQC"
        encoding = ifelse(grepl("^FEO-", algo_name), "FEO", "-") # "FEO" or "-"
    ) %>%
    inner_join(
        active_kems,
        by = c("algo" = "algo")
    ) %>%
    mutate(
        order = match(nist_level, c("L0", "L1", "L3", "L5")),
        algo = reorder(algo, order)
    )

n <- data_kems %>%
    group_by(algo, op) %>%
    equal_group_size()

df_oqs <- df_oqs %>%
    group_by(algo, op) %>%
    summarise(
        perf_supercop_mean = mean(perf),
        perf_supercop_sd = sd(perf),
        .groups = "drop"
    )

data_kems %>%
    group_by(algo, op) %>%
    summarise(
        perf_ours_mean = mean(perf),
        perf_ours_sd = sd(perf),
        base_kem = first(base_kem),
        encoding = first(encoding),
        .groups = "drop"
    ) %>%
    left_join(
        df_oqs,
        by = c("algo" = "algo", "op" = "op")
    ) %>%
    pivot_longer(
        !c(algo, op, base_kem, encoding),
        names_to = c("origin", "metric"),
        names_pattern = "perf_(.*)_(.*)",
        values_to = "value",
    ) %>%
    pivot_wider(
        names_from = metric,
        values_from = value
    ) %>%
    mutate(
        origin = reorder(origin, match(origin, rev(origin)))
    ) %>%
    ggplot(aes(y = mean, x = algo, color = op, shape = origin, alpha = origin)) +
    ggtitle(paste0("(O)KEM Running Time (n=", n, ")")) +
    labs(color = "Operation", shape = "Data Set") +
    xlab("Benchmark name") +
    ylab("log Running time [ms/op]") +
    theme(legend.position = "left", axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_alpha_manual(values = c(0.7, 1)) +
    guides(alpha = "none") +
    scale_shape_manual(values = c(4, 16)) +
    scale_y_continuous(trans = "log10") +
    geom_point(position = position_dodge(1), size = 2) +
    # geom_errorbar(aes(ymin = mean - sd, ymax = mean + sd), position = position_dodge(1), width = 1, alpha=0.5) +
    facet_nested(~ base_kem + encoding, scales = "free_x", space = "free")

data_kems %>%
    group_by(algo, op) %>%
    summarise(
        mean = mean(bytes.alloc),
        sd = sd(bytes.alloc),
        base_kem = first(base_kem),
        encoding = first(encoding),
        .groups = "drop"
    ) %>%
    ggplot(aes(y = mean, x = algo, color = op)) +
    scale_fill_manual(
        values = c(
            "#F8766D", "#00BA38", "#619CFF",
            "lightgrey", "grey", "darkgrey"
        ),
    ) +
    ggtitle(paste0("(O)KEM Memory Usage (n=", n, ")")) +
    labs(color = "Operation") +
    xlab("Benchmark name") +
    ylab("log Bytes allocated [B/op]") +
    theme(legend.position = "left", axis.text.x = element_text(angle = 45, hjust = 1)) +
    scale_y_continuous(trans = "log10") +
    geom_point(position = position_dodge(1), size = 2) +
    # geom_errorbar(aes(ymin = mean - sd, ymax = mean + sd), position = position_dodge(1), width = 1) +
    facet_nested(~ base_kem + encoding, scales = "free_x", space = "free")

# ---------- TRAFFIC DATA ----------
transform_traffic <- function(data, size_column, granularity) {
    df <- data %>%
        # Bin data in 100ms regions, keep all other columns
        mutate(
            time_bin = round(timestamp, granularity)
        ) %>%
        group_by(.data$transport, .data$packet_type, .data$direction, .data$replicate, .data$time_bin) %>%
        summarise(kbps = 8 * sum({{ size_column }}) / 10^-granularity / 1000, .groups = "drop")

    n <- df %>%
        group_by(.data$transport, .data$packet_type, .data$direction, .data$replicate) %>%
        summarise(n = n(), .groups = "drop") %>%
        group_by(.data$transport, .data$packet_type, .data$direction) %>%
        equal_group_size()

    # Average traffic over replicates, ensure all replicas have values (even 0) at all time_bins
    df <- df %>%
        group_by(.data$time_bin) %>%
        complete(.data$transport, .data$packet_type, .data$direction, .data$replicate, fill = list(kbps = 0)) %>%
        group_by(.data$transport, .data$packet_type, .data$direction, .data$time_bin) %>%
        summarise(kbps = mean(.data$kbps), .groups = "drop") %>%
        # Remove direction column, but negate traffic with downstream flow (2 rows for kbps)
        mutate(
            kbps = ifelse(.data$direction == "upstream", .data$kbps, -.data$kbps)
        )

    list(n, df)
}

# Shows traffic over entire test with peers and type colored
print("---- data_traffic_overview ----")
c(n, data_traffic_overview) %<-% (
    data_traffic %>%
        transform_traffic(TCP.payload.size, 2 - max_handshakes)
)

data_traffic_overview %>%
    filter(time_bin < 10) %>%
    mutate( # Example: "Drivel (L3b)"
        transport_type = sub(" \\(.*$", "", transport), # "Drivel"
    ) %>%
    group_by(time_bin, transport_type, packet_type, direction) %>%
    # because we lump all parameter sets together, we need to average upstream and downstream at each timepoint
    summarise(kbps = mean(kbps), .groups = "drop") %>%
    ggplot(aes(y = kbps, x = time_bin, fill = packet_type)) +
    ggtitle(paste0("Network Traffic over Time (TCP payloads, n=", n, ")")) +
    labs(fill = "Packet type (peer)") +
    xlab("Time since first packet [s]") +
    ylab("Network traffic [kbps]") +
    geom_col(position = "stack") +
    facet_wrap(~transport_type, ncol = 1)


# Shows traffic in handshake only but more detailed
print("---- data_traffic_handshake ----")
c(n, data_traffic_handshake) %<-% (
    data_traffic %>%
        filter(grepl("handshake", packet_type)) %>%
        transform_traffic(key.exchange.size, 4 - max_handshakes)
)

# Totals do sum-per-replicate and mean-over-replicates, as there may be data split over multiple packets
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
    filter(time_bin * 1000 < 35) %>%
    mutate( # Example: "Drivel (L3b)"
        transport_type = sub("[abcd]\\)$", ")", transport), # "Drivel (L3)"
        transport_letter = ifelse(grepl("L0|obfs4", transport), # "b" or "a" for obfs4
            "a", # default letter for L0 and obfs4
            sub("^.*L\\d", "", sub("\\)", "", transport))
        )
    ) %>%
    ggplot(aes(y = kbps, x = time_bin * 1000, fill = transport_letter)) +
    ggtitle(paste0("Traffic for Key Exchange (TCP payloads, n=", n, ")")) +
    xlab("Time since client Tor startup [ms]") +
    ylab("Network traffic [kbps]") +
    scale_x_continuous(n.breaks = 10) +
    geom_col() +
    guides(fill = "none") + # hides "transport_letter" from legend
    facet_wrap(~transport_type, ncol = 1, scales = "free_y")
p2 <- data_traffic_handshake_totals %>%
    mutate( # Example: "Drivel (L3b)"
        transport_type = sub("[abcd]\\)$", ")", transport), # "Drivel (L3)"
        transport_subid = sub("\\)$", "", sub(".* \\(", "", transport)), # "L3a"
        transport_letter = ifelse(grepl("L0|obfs4", transport), # "b" or "a" for obfs4
            "a", # default letter for L0 and obfs4
            sub("^.*L\\d", "", sub("\\)", "", transport))
        )
    ) %>%
    ggplot(aes(y = total, x = transport_subid, label = total, fill = transport_letter)) +
    ggtitle("Total bytes") +
    xlab("Drivel parameter set") +
    ylab("Total traffic volume [B]") +
    geom_col() +
    geom_bar_text() +
    guides(fill = "none") + # hides "transport_letter" from legend
    facet_wrap(~transport_type, ncol = 1, scales = "free")

ggarrange(p1, p2,
    nrow = 1, align = "h",
    widths = c(2, 1),
    common.legend = TRUE
)

# Shows frequency distribution of TCP payload sizes
print("---- data_traffic ----")
data_traffic_hist <- data_traffic %>%
    mutate( # Example: "Drivel (L3b)"
        transport_type = sub("[abcd]\\)$", ")", transport), # "Drivel (L3)"
        transport_subid = sub("\\)$", "", sub(".* \\(", "", transport)), # "L3a"
        transport_letter = ifelse(grepl("L0|obfs4", transport), # "b" or "" for obfs4
            "a", # default letter for L0 and obfs4
            sub("^.*L\\d", "", sub("\\)", "", transport))
        ),
        TCP.packet.size = ifelse(packet_type == "data", TCP.payload.size + 32, TCP.payload.size + 40),
        bin = cut_width(log10(TCP.packet.size), width = 0.1),
        TCP.packet.size.binned = 10^round(log10(TCP.packet.size), digits = 1)
    ) %>%
    group_by(packet_type, transport_type, bin) %>%
    summarise(
        count = n(),
        TCP.packet.size = first(TCP.packet.size.binned),
        transport_type = first(transport_type),
        .groups = "drop"
    ) %>%
    group_by(packet_type, transport_type) %>%
    mutate(
        frequency_singletype = count / sum(count)
    ) %>%
    group_by(transport_type) %>%
    mutate(
        frequency_alltypes = count / sum(count)
    )

p1 <- data_traffic_hist %>%
    ggplot(aes(x = TCP.packet.size, y = frequency_alltypes, fill = packet_type)) +
    ggtitle("Distribution of all TCP Packet Sizes") +
    labs(fill = "Packet type (peer)") +
    xlab("log TCP packet size [B]") +
    ylab("Frequency [% of packets]") +
    guides(fill = guide_legend(nrow = 2), linetype = guide_legend(nrow = 2)) + # Number of rows for legend
    scale_y_continuous(labels = scales::percent) +
    scale_x_log10() +
    geom_col(width = 0.1) +
    geom_vline(aes(xintercept = 7240, linetype = "TCP Segmentation Size Limit (using GSO)"), colour = "red") +
    geom_vline(aes(xintercept = 1460, linetype = "TCP Maximum Segment Size (MSS)"), colour = "blue") +
    scale_linetype_manual(
        name = "Size limits",
        values = c("dotted", "dotted")
    ) +
    facet_wrap(~transport_type, ncol = 1, scales = "free_y")
p2 <- data_traffic_hist %>%
    filter(packet_type == "handshake (bridge)") %>%
    ggplot(aes(x = TCP.packet.size, y = frequency_singletype)) +
    ggtitle("Handshake Packets only") +
    labs(fill = "Packet type (peer)") +
    xlab("log TCP packet size [B]") +
    ylab("Frequency [% of handshake packets]") +
    scale_y_continuous(labels = scales::percent) +
    scale_x_log10() +
    geom_col(fill = "#619cff", width = 0.1) +
    geom_vline(aes(xintercept = 7240, linetype = "TCP Segmentation Size Limit (using GSO)"), colour = "red") +
    geom_vline(aes(xintercept = 1460, linetype = "TCP Maximum Segment Size (MSS)"), colour = "blue") +
    scale_linetype_manual(
        name = "Size limits",
        values = c("dotted", "dotted")
    ) +
    facet_wrap(~transport_type, ncol = 1, scales = "free_y")

ggarrange(p1, p2,
    nrow = 1, align = "h",
    widths = c(2, 1),
    common.legend = TRUE,
    legend = "bottom"
)

# Shows handshake packet contents by size (uses runs.csv, per transport and container - rest labels)
print("---- data_runs ----")
data_runs %>%
    mutate( # Example: "Drivel (L3b)"
        transport_type = sub("[abcd]\\)$", ")", transport), # "Drivel (L3)"
        transport_subid = sub("\\)$", "", sub(".* \\(", "", transport)) # "L3a"
    ) %>%
    ggplot(aes(x = container, y = size, fill = field)) +
    ggtitle("Composition of Handshake Packets") +
    xlab("Packet origin") +
    ylab("Field size [B]") +
    labs(fill = "Field") +
    guides(fill = guide_legend(nrow = 3), linetype = guide_legend(nrow = 2)) + # Number of rows for legend
    scale_y_continuous(breaks = function(z) seq(0, range(z)[2], by = 2^(floor(log2(max(z))) - 2))) +
    geom_col() +
    geom_hline(aes(yintercept = 7240, linetype = "TCP Segmentation Size Limit (using GSO)"), colour = "red") +
    geom_hline(aes(yintercept = 1460, linetype = "TCP Maximum Segment Size (MSS)"), colour = "blue") +
    scale_linetype_manual(
        name = "Size limits",
        values = c("dotted", "dotted")
    ) +
    theme(legend.position = "bottom", axis.text.x = element_text(angle = 45, hjust = 1)) +
    facet_nested(~ transport_type + transport_subid)

warnings()
