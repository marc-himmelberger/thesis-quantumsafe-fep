#!/usr/bin/env python3
from pathlib import Path
import re
import shutil

import pandas as pd
from scapy.all import *
from scapy.layers.inet import IP, TCP

# This file parses Go benchmark logs and Docker logs into structured data for use in R.

RESULTS_FOLDER = Path("results")
OUT_FOLDER = RESULTS_FOLDER.joinpath("structured")

BRIDGE_IP = "172.16.113.5"
CLIENT_IP = "172.16.113.6"


def structure_benchmarks(folder_bench: Path) -> pd.DataFrame:
    """Benchmarks: branch, benchmark, subbench, cpus, iter, time/iter, bytes alloc, allocs"""

    df = pd.DataFrame(
        columns=[
            "branch",
            "benchmark",
            "subbench",
            "cpus",
            "iter",
            "time/iter",  # [ns/op]
            "bytes alloc",  # [B/op]
            "allocs",  # [allocs/op]
        ]
    )

    for path_txt in folder_bench.glob("*.txt"):
        branch_name = path_txt.with_suffix("").name

        curr_pkg: str = ""
        with open(path_txt, "r") as f:
            for line in f.readlines():
                if line.startswith("pkg: "):
                    curr_pkg = line[5:]
                    assert curr_pkg.startswith(
                        "gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird/"
                    ), "Benchmark from non-lyrebird package"
                    curr_pkg = curr_pkg[72:]
                    continue
                elif line.startswith("cpu: "):
                    continue
                elif line.startswith("PASS"):
                    curr_pkg = ""
                    continue
                elif curr_pkg != "":
                    values = [v.strip() for v in line.split("\t")]

                    # BenchmarkKems/FrodoKEM-1344-SHAKE-Decaps-16
                    benchmark = "-".join(values[0].split("-")[:-1])
                    cpus = values[0].split("-")[-1]

                    subbench = "/".join(benchmark.split("/")[1:])
                    benchmark = benchmark.split("/")[0]

                    entry = pd.DataFrame.from_dict(
                        {
                            "branch": [branch_name],
                            "benchmark": [curr_pkg + " " + benchmark],
                            "subbench": [subbench],
                            "cpus": [cpus],
                            "iter": [values[1]],
                            "time/iter": [values[2].split(" ")[0]],
                            "bytes alloc": [values[3].split(" ")[0]],
                            "allocs": [values[4].split(" ")[0]],
                        }
                    )
                    df = pd.concat([df, entry], ignore_index=True)

    return df


def structure_runs(folder_runs: Path) -> tuple[pd.DataFrame, pd.DataFrame]:
    """
    logs:
        - did the tests work
        - was the expected protocol used
        - how much padding was used (should be fixed number)
        - what sizes are the various components
    tcpdump:
        - should have only two non-loopback TCP streams (extIP and bridge)
        - exact timing of handshake messages
        - sizes of first two messages in detail
        - visualization of packet content of first two messages
        - packets from both TCP streams (including time, directionality, purpose and size)
    Output as one or more data frames
    """

    # One row per container (client, bridge) and per run
    df_runs = pd.DataFrame(
        columns=[
            "protocol",  # obfs4 | drivel
            "run config",  # x25519, etc (see benchmark.sh: ensure_drivel_*)
            "container",  # client | bridge
            "handshakes",  # number of handshakes observed in logs
            "padding size",  # [B]
            "KEM public key size",  # [B]
            "KEM ciphertext size",  # [B]
            "OKEM ciphertext size",  # [B]
            "mark size",  # [B]
            "mac size",  # [B]
            "auth size",  # [B]
        ]
    )
    # One row per relevant packet
    df_traffic = pd.DataFrame(
        columns=[
            "protocol",  # obfs4 | drivel
            "run config",  # x25519, etc (see benchmark.sh: ensure_drivel_*)
            "type",  # handshake | data
            "peer",  # bridge | extIP
            "timestamp",
            "direction",  # upstream | downstream
            "TCP payload size",  # [B]
            "key exchange size",  # [B]
        ]
    )

    for run_folder in folder_runs.glob("*"):
        assert len(run_folder.name.split("-")) in [1, 2], "Bad run config name"
        run_protocol = run_folder.name.split("-")[0]
        run_config = None
        try:
            run_config = run_folder.name.split("-")[1]
        except IndexError:
            pass

        padding_client: int | None = None
        padding_bridge: int | None = None
        size_kem_pk: int | None = None
        size_kem_ctxt: int | None = None
        size_okem_ctxt: int | None = None
        size_mark: int | None = None
        size_mac: int | None = None
        size_auth: int | None = None

        num_handshakes: int | None = None

        # Handle Docker logs
        for log_file in run_folder.joinpath("logs").glob("*.log"):
            container_name = log_file.with_suffix("").name
            with open(log_file, "r") as f:
                logs = f.read()

            if container_name.endswith("-logs"):
                container_type = container_name[:-5]

                _num_handshakes = logs.count(".generateHandshake()")
                if num_handshakes is None:
                    num_handshakes = _num_handshakes
                else:
                    assert (
                        num_handshakes == _num_handshakes
                    ), "Inconsistent number of handshakes logged"

                m = re.search(container_type + r" padding range \[(\d+), (\d+)\]", logs)
                # In case the log line does not indicate client/server padding, deduce from container_type
                if m is None:
                    m = re.search(r"padding range \[(\d+), (\d+)\]", logs)
                    assert m

                assert m, "Unable to find padding range in logs"
                assert len(m.groups()) == 2, "Unable to parse padding range in logs"

                pad_min = m.group(1)
                pad_max = m.group(2)
                assert pad_min == pad_max, "Padding not fixed"
                pad = int(pad_min)

                match container_type:
                    case "client":
                        padding_client = pad
                    case "bridge":
                        padding_bridge = pad
                    case _:
                        assert False, "Unknown container type"

                if run_folder.name.startswith("drivel"):
                    assert (
                        "completed a handshake and has wrapped its connection" in logs
                    )

                    # Extract all sizes from logs, compare with saved or update
                    _size_kem_pk = re.search(r"size_kem_pk (\d+)", logs)
                    assert _size_kem_pk is not None and len(_size_kem_pk.groups()) == 1
                    _size_kem_pk = int(_size_kem_pk.group(1))
                    _size_kem_ctxt = re.search(r"size_kem_ctxt (\d+)", logs)
                    assert (
                        _size_kem_ctxt is not None and len(_size_kem_ctxt.groups()) == 1
                    )
                    _size_kem_ctxt = int(_size_kem_ctxt.group(1))
                    _size_okem_ctxt = re.search(r"size_okem_ctxt (\d+)", logs)
                    assert (
                        _size_okem_ctxt is not None
                        and len(_size_okem_ctxt.groups()) == 1
                    )
                    _size_okem_ctxt = int(_size_okem_ctxt.group(1))
                    _size_mark = re.search(r"size_mac (\d+)", logs)
                    assert _size_mark is not None and len(_size_mark.groups()) == 1
                    _size_mark = int(_size_mark.group(1))
                    _size_mac = re.search(r"size_mac (\d+)", logs)
                    assert _size_mac is not None and len(_size_mac.groups()) == 1
                    _size_mac = int(_size_mac.group(1))
                    _size_auth = re.search(r"size_auth (\d+)", logs)
                    assert _size_auth is not None and len(_size_auth.groups()) == 1
                    _size_auth = int(_size_auth.group(1))

                    if size_kem_pk is None:
                        size_kem_pk = _size_kem_pk
                    else:
                        assert size_kem_pk == _size_kem_pk, "Inconsistent size_kem_pk"
                    if size_kem_ctxt is None:
                        size_kem_ctxt = _size_kem_ctxt
                    else:
                        assert (
                            size_kem_ctxt == _size_kem_ctxt
                        ), "Inconsistent size_kem_ctxt"
                    if size_okem_ctxt is None:
                        size_okem_ctxt = _size_okem_ctxt
                    else:
                        assert (
                            size_okem_ctxt == _size_okem_ctxt
                        ), "Inconsistent size_okem_ctxt"
                    if size_mark is None:
                        size_mark = _size_mark
                    else:
                        assert size_mark == _size_mark, "Inconsistent size_mark"
                    if size_mac is None:
                        size_mac = _size_mac
                    else:
                        assert size_mac == _size_mac, "Inconsistent size_mac"
                    if size_auth is None:
                        size_auth = _size_auth
                    else:
                        assert size_auth == _size_auth, "Inconsistent size_auth"
                elif run_folder.name.startswith("obfs4"):
                    # statically known, no need to parse logs
                    size_kem_pk = 32  # X'
                    size_kem_ctxt = 32  # Y'
                    size_okem_ctxt = 0  # -
                    size_mark = 16  # M_C, M_S
                    size_mac = 16  # MAC_C, MAC_S
                    size_auth = 32  # auth

                entry_padding = pd.DataFrame.from_dict(
                    {
                        "protocol": [run_protocol],
                        "run config": [run_config],
                        "container": [container_type],
                        "handshakes": [num_handshakes],
                        "padding size": [pad],
                        "KEM public key size": [size_kem_pk],
                        "KEM ciphertext size": [size_kem_ctxt],
                        "OKEM ciphertext size": [size_okem_ctxt],
                        "mark size": [size_mark],
                        "mac size": [size_mac],
                        "auth size": [size_auth],
                    }
                )
                df_runs = pd.concat([df_runs, entry_padding], ignore_index=True)
            elif container_name == "client":
                assert "[PASS] Received a new IP" in logs, "Client logs contain no pass"
                assert "[FAIL]" not in logs, "Client logs contain failure"

                regular_ip_str = re.search(r"Regular IP: (.*)", logs)
                assert regular_ip_str is not None and len(regular_ip_str.groups()) == 1
                torify_ip_str = re.search(r"Torify IP: (.*)", logs)
                assert torify_ip_str is not None and len(torify_ip_str.groups()) == 1

                regular_ip = json.loads(regular_ip_str.group(1))
                torify_ip = json.loads(torify_ip_str.group(1))

                assert "ip" in regular_ip, "Regular IP not found"
                if "error" in torify_ip:
                    assert (
                        torify_ip["error"] == "Too Many Requests"
                    ), "Torify IP: unknown error"
                else:
                    assert "ip" in torify_ip, "Torify IP not found"
                    assert regular_ip["ip"] != torify_ip["ip"], "IPs shouldn't match"
            elif container_name == "bridge":
                assert f"transport '{run_protocol}'" in logs, "Protocol not found"
                assert "Bootstrapped 100% (done): Done" in logs, "Bridge setup not done"
            elif container_name.startswith("tcpdump"):
                num_packets = re.search(r"(\d+) packets captured", logs)
                assert num_packets is not None and len(num_packets.groups()) == 1
                num_packets = int(num_packets.group(1))
                assert num_packets > 10
            else:
                assert False, "Unknown container name"

        print(f"parsed logs files: {run_folder}")

        assert isinstance(padding_client, int), "Missing value for: padding_client"
        assert isinstance(padding_bridge, int), "Missing value for: padding_bridge"
        assert isinstance(size_kem_pk, int), "Missing value for: size_kem_pk"
        assert isinstance(size_kem_ctxt, int), "Missing value for: size_kem_ctxt"
        assert isinstance(size_okem_ctxt, int), "Missing value for: size_okem_ctxt"
        assert isinstance(size_mark, int), "Missing value for: size_mark"
        assert isinstance(size_mac, int), "Missing value for: size_mac"
        assert isinstance(size_auth, int), "Missing value for: size_auth"
        assert isinstance(num_handshakes, int), "Missing value for: num_handshakes"

        class ClientHs(Packet):
            name = "ClientHs "
            fields_desc: list = [
                StrFixedLenField("KEM_pk", default=None, length=size_kem_pk),
                StrFixedLenField(
                    "OKEM_ciphertext", default=None, length=size_okem_ctxt
                ),
                StrFixedLenField("padding", default=None, length=padding_client),
                StrFixedLenField("mark", default=None, length=size_mark),
                StrFixedLenField("mac", default=None, length=size_mac),
            ]

        required_client_hs_len = (
            size_kem_pk + size_okem_ctxt + padding_client + size_mark + size_mac
        )

        class BridgeHs(Packet):
            name = "BridgeHs "
            fields_desc: list = [
                StrFixedLenField("KEM_ctxt", default=None, length=size_kem_ctxt),
                StrFixedLenField("auth_value", default=None, length=size_auth),
                StrFixedLenField("padding", default=None, length=padding_bridge),
                StrFixedLenField("mark", default=None, length=size_mark),
                StrFixedLenField("mac", default=None, length=size_mac),
            ]

        required_bridge_hs_len = (
            size_kem_ctxt + size_auth + padding_bridge + size_mark + size_mac
        )

        # Handle tcpdump
        packets = rdpcap(str(run_folder.joinpath("tcpdump", "tcpdump.pcap")))

        extIP_ip = None
        tcp_bridge: list[Packet] = []
        tcp_extIP: list[Packet] = []
        for p in packets:
            if p.haslayer(TCP):
                ip: IP = p[IP]
                if ip.src == "127.0.0.1":
                    # exclude loopback packets
                    continue
                if ip.src == BRIDGE_IP or ip.dst == BRIDGE_IP:
                    tcp_bridge.append(p)
                else:
                    if extIP_ip is None:
                        assert ip.src == CLIENT_IP, "Unexpected extra TCP traffic"
                        extIP_ip = ip.dst
                    else:
                        assert (ip.src == CLIENT_IP and ip.dst == extIP_ip) or (
                            ip.src == extIP_ip and ip.dst == CLIENT_IP
                        ), "Unexpected extra TCP traffic"
                    tcp_extIP.append(p)

        syn_packet_indices = []
        for i, p in enumerate(tcp_bridge):
            if p[TCP].flags != "S":
                continue
            # We could also weed out the former indices, in case TCP fails
            assert (
                len(syn_packet_indices) == 0 or i >= syn_packet_indices[-1] + 7
            ), "SYN packets too close for handshakes"
            syn_packet_indices.append(i)

        assert (
            len(syn_packet_indices) == num_handshakes
        ), "Expected number of handshakes does not match SYN packets to bridge"
        print(f"found {num_handshakes} handshakes: {run_folder}")

        # tuples of indices for handshake packet regions (start inclusive, end exclusive)
        handshake_packet_regions: list[tuple[int, int]] = []
        for i, start_index in enumerate(syn_packet_indices):
            handshake: list[Packet] = tcp_bridge[start_index : start_index + 3]
            assert handshake[0][TCP].flags == "S", "1st not SYN"
            assert handshake[1][TCP].flags == "SA", "2nd not SYN, ACK"
            assert handshake[2][TCP].flags == "A", "3rd not ACK"

            # index of the first packet not used for handshake data
            next_index = start_index + 3
            # bytestrings containing data from relevant packets, possibly with some excess
            client_hs_data: bytes = b""
            bridge_hs_data: bytes = b""

            while len(client_hs_data) < required_client_hs_len:
                # consume two more packets, push+ack (upstream) and ack (downstream)
                assert (
                    tcp_bridge[next_index][TCP].flags == "PA"
                ), "missing client_hs data, but next is not PSH, ACK"
                assert (
                    tcp_bridge[next_index][IP].src == CLIENT_IP
                ), "missing client_hs data, but next is not upstream"
                assert (
                    tcp_bridge[next_index + 1][TCP].flags == "A"
                ), "missing client_hs data, but 2nd next is not ACK"
                assert (
                    tcp_bridge[next_index + 1][IP].dst == CLIENT_IP
                ), "missing client_hs data, but 2nd next is not downstream"

                handshake.extend(tcp_bridge[next_index : next_index + 2])
                client_hs_data += tcp_bridge[next_index][TCP].payload.load
                next_index += 2
            assert (
                len(client_hs_data) == required_client_hs_len
            ), "Client sent excessive data"

            while len(bridge_hs_data) < required_bridge_hs_len:
                # consume two more packets, push+ack (downstream) and ack (upstream)
                assert (
                    tcp_bridge[next_index][TCP].flags == "PA"
                ), "missing bridge_hs data, but next is not PSH, ACK"
                assert (
                    tcp_bridge[next_index][IP].dst == CLIENT_IP
                ), "missing bridge_hs data, but next is not downstream"
                assert (
                    tcp_bridge[next_index + 1][TCP].flags == "A"
                ), "missing bridge_hs data, but 2nd next is not ACK"
                assert (
                    tcp_bridge[next_index + 1][IP].src == CLIENT_IP
                ), "missing bridge_hs data, but 2nd next is not upstream"

                handshake.extend(tcp_bridge[next_index : next_index + 2])
                bridge_hs_data += tcp_bridge[next_index][TCP].payload.load
                next_index += 2
            assert (
                len(bridge_hs_data) > required_bridge_hs_len
            ), "Bridge did not send excessive data"

            handshake_packet_regions.append((start_index, next_index))

            client_hs_pkt = ClientHs(client_hs_data)
            bridge_hs_pkt = BridgeHs(bridge_hs_data)

            assert len(client_hs_pkt) == len(client_hs_data), "Client packet lost data"
            assert len(bridge_hs_pkt) == len(bridge_hs_data), "Bridge packet lost data"

            with open(
                run_folder.joinpath("tcpdump", f"handshake-{i+1}.txt"),
                "w",
                encoding="utf-8",
            ) as f:
                msg1 = client_hs_pkt.show(dump=True)
                msg2 = bridge_hs_pkt.show(dump=True)

                assert isinstance(msg1, str) and isinstance(msg2, str)
                f.write(msg1 + "\n")
                f.write(msg2 + "\n")

            print(f"  processed handshake {i+1}")
            # Commented out as it takes a rather long time to render and is not very useful for larger settings
            #
            # print(f"    drawing client handshake {i+1}", end="")
            # client_hs_pkt.pdfdump(
            #     str(run_folder.joinpath("tcpdump", f"handshake-client-{i+1}.pdf"))
            # )
            # print(f"    drawing bridge handshake {i+1}", end="")
            # bridge_hs_pkt.pdfdump(
            #     str(run_folder.joinpath("tcpdump", f"handshake-bridge-{i+1}.pdf"))
            # )

            # Remove any excess data in packets for analysis
            client_hs_pkt.remove_payload()
            bridge_hs_pkt.remove_payload()
            assert len(client_hs_pkt) == len(
                client_hs_data
            ), "Client packet had payload?"
            assert len(bridge_hs_pkt) < len(
                bridge_hs_data
            ), "Bridge packet had no payload?"

            # TODO add an entry for each PSH+ACK packet in handshake
            psh_ack_packets = [p for p in handshake if p[TCP].flags == "PA"]
            # How much of each TCP payload was used for key exchange (i.e. not for inlineseedframe)
            key_ex_sizes = []
            remaining_client_hs_len = required_client_hs_len
            remaining_bridge_hs_len = required_bridge_hs_len
            for p in psh_ack_packets:
                payload_len = len(p[TCP].payload)
                if p[IP].src == CLIENT_IP:
                    assert (
                        remaining_client_hs_len > 0
                        and remaining_client_hs_len >= payload_len
                    ), "BUG: too much client data"
                    key_ex_sizes.append(payload_len)
                    remaining_client_hs_len -= payload_len
                else:
                    assert remaining_bridge_hs_len > 0, "BUG: too much client data"
                    keyex_data_len = min(remaining_bridge_hs_len, payload_len)
                    key_ex_sizes.append(keyex_data_len)
                    remaining_bridge_hs_len -= keyex_data_len
            assert (
                remaining_client_hs_len == 0
            ), "Incomplete distribution of client TCP payload lengths to key exchange sizes"
            assert (
                remaining_bridge_hs_len == 0
            ), "Incomplete distribution of bridge TCP payload lengths to key exchange sizes"

            entries_hs = pd.DataFrame.from_dict(
                {
                    "protocol": run_protocol,
                    "run config": run_config,
                    "type": "handshake",
                    "peer": "bridge",
                    "timestamp": [p.time for p in psh_ack_packets],
                    "direction": [
                        "upstream" if p[IP].src == CLIENT_IP else "downstream"
                        for p in psh_ack_packets
                    ],
                    "TCP payload size": [len(p[TCP].payload) for p in psh_ack_packets],
                    "key exchange size": key_ex_sizes,
                }
            )
            df_traffic = pd.concat([df_traffic, entries_hs], ignore_index=True)
        for i, p in enumerate(tcp_bridge):
            # skip handshake packets, add rest
            if any(
                i >= start_index and i < next_index
                for (start_index, next_index) in handshake_packet_regions
            ):
                continue
            entry_tunnel = pd.DataFrame.from_dict(
                {
                    "protocol": run_protocol,
                    "run config": run_config,
                    "type": ["data"],
                    "peer": ["bridge"],
                    "timestamp": p.time,
                    "direction": [
                        "upstream" if p[IP].src == CLIENT_IP else "downstream"
                    ],
                    "TCP payload size": [len(p[TCP].payload)],
                    "key exchange size": [pd.NA],
                }
            )
            df_traffic = pd.concat([df_traffic, entry_tunnel], ignore_index=True)
        entries_extIP = pd.DataFrame.from_dict(
            {
                "protocol": run_protocol,
                "run config": run_config,
                "type": ["data"] * len(tcp_extIP),
                "peer": ["extIP"] * len(tcp_extIP),
                "timestamp": [p.time for p in tcp_extIP],
                "direction": [
                    "upstream" if p[IP].src == CLIENT_IP else "downstream"
                    for p in tcp_extIP
                ],
                "TCP payload size": [len(p[TCP].payload) for p in tcp_extIP],
                "key exchange size": [pd.NA] * len(tcp_extIP),
            }
        )
        df_traffic = pd.concat([df_traffic, entries_extIP], ignore_index=True)

    return df_runs, df_traffic


def main():
    assert RESULTS_FOLDER.exists()
    if OUT_FOLDER.exists():
        shutil.rmtree(OUT_FOLDER)
    OUT_FOLDER.mkdir()

    df_bench: pd.DataFrame | None = None
    df_runs: pd.DataFrame | None = None
    df_traffic: pd.DataFrame | None = None

    for repl_folder in sorted(RESULTS_FOLDER.glob("bench-*")):
        repl = int(repl_folder.name[6:])
        benchmarks_folder = repl_folder.joinpath("benchmarks")
        runs_folder = repl_folder.joinpath("runs")

        if benchmarks_folder.exists():
            data_bench = structure_benchmarks(benchmarks_folder)
            data_bench["replicate"] = repl

            df_bench = (
                data_bench
                if df_bench is None
                else pd.concat([df_bench, data_bench], ignore_index=True)
            )
        if runs_folder.exists():
            data_runs, data_traffic = structure_runs(runs_folder)
            data_runs["replicate"] = repl
            data_traffic["replicate"] = repl

            df_runs = (
                data_runs
                if df_runs is None
                else pd.concat([df_runs, data_runs], ignore_index=True)
            )
            df_traffic = (
                data_traffic
                if df_traffic is None
                else pd.concat([df_traffic, data_traffic], ignore_index=True)
            )

    assert df_bench is not None and df_runs is not None and df_traffic is not None

    df_bench.to_csv(OUT_FOLDER.joinpath("benchmarks.csv"))
    df_runs.to_csv(OUT_FOLDER.joinpath("runs.csv"))
    df_traffic.to_csv(OUT_FOLDER.joinpath("traffic.csv"))


if __name__ == "__main__":
    main()
