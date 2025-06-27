# thesis-quantumsafe-fep

## Name
Implementing and Evaluating Quantum-Safe Fully Encrypted Protocols

## The Thesis
 
My Master's Thesis consists mainly of the implementation of the "drivel" pluggable transport [[1]](#1).

Drivel is an evolution of obfs4 [[2]](#2) that:

- allows for key encapsulation mechanisms, particularly the ones proposed as part of the NIST standardization [[3]](#3),
- has stronger security guarantees than obfs4 in the scenario that censors should get ahold of bridge information such as NodeID and long-term public key,
- contains a thin crypto-agility layer, allowing the replacement of cryptographic algorithms as needed, and
- provides more choice to bridge operators regarding performance trade-offs

Additionally, there are proposed changes to drivel itself, evaluations of the implementation's performance and some security proofs in the thesis.

The thesis PDF is available under:
TODO ETH LINK OR IACR  
The initial thesis proposal is documented in this repository under: [docs/Proposal_MSc_Thesis.pdf](docs/Proposal_MSc_Thesis.pdf)  
The LaTeX sources for the thesis are contained in the folder [latex](latex).

Implementers should focus on the less theoretical chapters "Implementing Drivel" and "Experimental Evaluation".

The implementation is done as a fork of the lyrebird repository [[4]](#4) and is available under: https://github.com/marc-himmelberger/lyrebird-drivel


The Tor Project is more than welcome to use my work for future changes to lyrebird.
In case of any feedback or questions, do not hesitate to reach out via E-Mail.

## Deploying Drivel

The following guide is reproduced from the "Implementing Drivel" chapter of the thesis PDF.

---

Note that this setup procedure is not geared towards end users, and a more user-friendly procedure is required for wide-spread deployment.
However, since this involves multiple changes to the current distribution mechanisms and drivel may be further adapted before then, we believe that further improvements are premature at this point.

In order to deploy our implementation of drivel as a Tor pluggable transport, we recommend the following procedure:

1. Clone our [fork of the lyrebird repository](https://github.com/marc-himmelberger/lyrebird-drivel) into a new directory called ``lyrebird''
    
2. Clone the official Tor repository containing recommended container files from the [docker-obfs4-bridge](https://gitlab.torproject.org/tpo/anti-censorship/docker-obfs4-bridge) repository into another directory called ``docker'' next to the one you just created
    
3. Adapt the files of `docker-obfs4-bridge` to match the contents of the corresponding files in the [docker/bridge](docker/bridge) folder in this repository. This changes the build process to not use the official lyrebird repository but instead copy the contents of a local `lyrebird` folder, install all necessary build dependencies and perform the build. Additionally, the bridge-line format requires minor changes to the `get-bridge-line` and `start-tor.sh` files.

4. For production use, perform the following additional steps:
    
    a. Remove the file `wrapper.sh`, and delete the following lines from the file `Dockerfile`

    ```
    COPY docker/bridge/wrapper.sh /usr/bin/wrapper.sh
    RUN chmod +x /usr/bin/wrapper.sh
    ```

    b. Replace `/usr/bin/wrapper.sh` by `/usr/bin/lyrebird` in `start-tor.sh`

    c. Re-enable the publication of server descriptors and the bridge distribution by removing the following lines from `start-tor.sh`:

    ```
    PublishServerDescriptor 0
    BridgeDistribution none
    ```

5. The rest of the setup requires merely setting the correct environment variables and building the docker container. This is well described in the [official Tor guide](https://community.torproject.org/relay/setup/bridge/docker/), which references a `docker-compose.yml` file. Simply download this file, place it next to the two folders created above and replace the line `image: thetorproject/obfs4-bridge:latest` by the following three lines:

    ```
    build:
    context: .
    dockerfile: docker/bridge/Dockerfile
    ```

6. Additionally, make sure that you set the environment variable `TOR_PT_SERVER_TRANSPORT_OPTIONS` in the `docker-compose.yml` file. Specify the variables `kem-name` and `okem-name` to configure the schemes used by drivel. An example is:

```
TOR_PT_SERVER_TRANSPORT_OPTIONS="drivel:kem-name=ML-KEM-512;drivel:okem-name=FEO-Classic-McEliece-348864"
```

7. Finally, start the tor bridge using the command `docker-compose up -d` in the same directory as `docker-compose.yml`

To connect, clients then require the information output by `get-bridge-line` in the running docker container, and all JSON files in the folder `/var/lib/tor/pt_state/` whose name starts with `drivel_key-`.

For clients, the same procedure to compile the lyrebird repository can be reused. Additionally, an installation of Tor is required, the bridge-line should be added to the `torrc` file and the public key file should be placed into the folder `/var/lib/tor/pt_state`. This procedure is simpler as the format of bridge-lines does not have to be accounted for, and the main change is the use of a locally compiled lyrebird binary.

An example of such a setup can be seen in this repository, which is configured to run both a bridge and a client container locally in a very similar manner, albeit with more debugging options and automatic transfer of the bridge-line and public keys, thus the changes described above in Item 4.

## Running the Analysis Workflow

To re-run the thesis' analyses on the implementation:

- Make sure that the Lyrebird fork's submodule is also fetched, use `git clone --recurse-submodules` or `git submodule update --init`
- Benchmarks are run using `make bench` in the lyrebird folder and require a Go installation
- One-shot Docker deployments (using a parameter set provided via `TOR_PT_SERVER_TRANSPORT_OPTIONS`) can be started using `cd docker && ./exec_test.sh`
- The deployment measurements will be saved to the `docker/logs`, and `docker/tcpdump*` folders

## Contributing
This project is currently not open to contributions and I don't expect to make further changes to the implementation after the publication of the thesis.

## Authors and acknowledgment
I would like to extend my thanks first to my supervisors Shannon Veitch, Dr. Felix Günther and Prof. Dr. Kenny Paterson for guiding me towards this engaging topic and giving me the opportunity to apply my skills for both theoretical analyses as well as a practical implementation. Their ideas and feedback in every discussion served to improve my thesis tremendously and I am grateful for the chance to contribute to such a relevant topic.

In addition, I want to thank Dr. Keita Xagawa for his time and insights, which helped me better understand prior research in the space of anonymity of quantum-safe KEMs.

Finally, I thank my friends, colleagues, family, my fiancée, and our cat - for keeping me motivated, for listening to many overly-technical explanations of my thesis, and for supporting me in more ways than I can count throughout the entirety of my studies.

## License
See [LICENSE](LICENSE), note that code in the lyrebird submodule may be licensed differently.

## References
<a id="1">[1]</a> 
https://eprint.iacr.org/2025/408.pdf

<a id="2">[2]</a> 
https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird/-/blob/main/doc/obfs4-spec.txt

<a id="3">[3]</a> 
https://csrc.nist.gov/projects/post-quantum-cryptography

<a id="4">[4]</a> 
https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird