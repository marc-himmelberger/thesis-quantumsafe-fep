#!/usr/bin/env python3
from pathlib import Path
import shutil

import pandas as pd

# This file parses Go benchmark logs and Docker logs into structured data for use in R.

RESULTS_FOLDER = Path("results")
OUT_FOLDER = RESULTS_FOLDER.joinpath("structured")


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
                    curr_pkg = line[5:].split("/")[-1].strip()
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
                            "benchmark": [curr_pkg + "." + benchmark],
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


def main():
    assert RESULTS_FOLDER.exists()
    if OUT_FOLDER.exists():
        shutil.rmtree(OUT_FOLDER)
    OUT_FOLDER.mkdir()

    data_bench = structure_benchmarks(RESULTS_FOLDER.joinpath("benchmarks"))
    data_bench.to_csv(OUT_FOLDER.joinpath("benchmarks.csv"))


if __name__ == "__main__":
    main()
