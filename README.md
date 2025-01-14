# thesis-quantumsafe-fep

## Name
Implementing and Evaluating Quantum-Safe Fully Encrypted Protocols

## Introduction, Description, References
See [docs/Proposal_MSc_Thesis.pdf](docs/Proposal_MSc_Thesis.pdf)

## Notes
See [Notion](https://www.notion.so/MSc-Thesis-172b3139d28980ee8917f71ec2b4ba35?pvs=4)

## Status of Work Packages

**WP1 (January)**: Literature Review and Protocol Familiarization

- [ ] Reviewing the proposed construction in Obfuscated Key Exchange
- [ ] Reviewing the obfs4-spec.txt  and how it differentiates itself from VMess or Shadowsocks

**WP2 (February)**: Implementing pq-obfs

- [ ] Implementing pq-obfs with Kemeleon encoding as specified in Obfuscated Key Exchange in order to reach a proof-of-concept stage
- [ ] Evaluating performance and traffic overhead compared to the original obfs4 protocol
- [ ] Documenting the implementation

**WP3 (March/April)**: Designing and Evaluating Novel Encodings

- [ ] Designing novel encoding algorithms for quantum-safe KEMs that map public keys and ciphertexts to random bitstrings
- [ ] Instantiating pq-obfs with several KEMs and their related encodings
- [ ] Evaluating tradeoffs of different encodings of KEM public keys/ciphertexts

**WP4 (May)**: Extensions

- [ ] Experimenting with implementing different traffic patterns, such as arbitrary fragmentation of key exchange messages and/or more flexibility in clients to send arbitrary data
- [ ] Evaluating the efficacy of the protocol against blocking in censored regions

**WP5 (June)**: Finalization

- [ ] Finalizing the thesis report (Documentation, Publishing, Report)

## Installation, Requirements

- *TBD*

## Measuring

## Contributing
This project is currently not open to contributions.

## Authors and acknowledgment
Show your appreciation to those who have contributed to the project.

## License
See [LICENSE](LICENSE)
