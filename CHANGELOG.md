# Changelog

## [0.1.0](https://github.com/neurogenomics/jacquard/compare/v0.1.0...v0.1.0) (2026-09-30)


### Added

* adapter and quality trimming for the scRNA and scTIP arms ([7981847](https://github.com/neurogenomics/jacquard/commit/79818476287b1ff639ff6247ad9b5c9b3b5784a4))
* add the --stop_after stage flag ([a83a30a](https://github.com/neurogenomics/jacquard/commit/a83a30a069c7141d54b52727dd0ff0a1c66f601d)), closes [#8](https://github.com/neurogenomics/jacquard/issues/8)
* add the arm fan-out and the per-arm read-count gate ([da31747](https://github.com/neurogenomics/jacquard/commit/da317471dc73c27fc52f37e6074c91efcc310543)), closes [#5](https://github.com/neurogenomics/jacquard/issues/5)
* add the carmack_readprep subworkflow with R2 carry-through ([a57a5b5](https://github.com/neurogenomics/jacquard/commit/a57a5b5fdf8ce36949c6597b3ae89992b05759c4)), closes [#4](https://github.com/neurogenomics/jacquard/issues/4)
* add the four carmack read-prep modules ([1a1a8fd](https://github.com/neurogenomics/jacquard/commit/1a1a8fd34b18f7b9119f1acb789b9a48db2e85e6)), closes [#3](https://github.com/neurogenomics/jacquard/issues/3)
* add the scRNA arm with per-arm FastQC and STARsolo ([b4a3c65](https://github.com/neurogenomics/jacquard/commit/b4a3c65dfdbb2a02c57a36894168187b1df7e79a)), closes [#6](https://github.com/neurogenomics/jacquard/issues/6)
* add the scTIP arm with QNAME retagging and umi_tools dedup ([4d005c8](https://github.com/neurogenomics/jacquard/commit/4d005c875c41c15be9ab43f86cefa40e29052fcb)), closes [#7](https://github.com/neurogenomics/jacquard/issues/7)
* bump carmack to 6816691 and finish the MultiQC integration ([5b8c7d8](https://github.com/neurogenomics/jacquard/commit/5b8c7d8f5037540822de3da20b9f5f24e076866c)), closes [#9](https://github.com/neurogenomics/jacquard/issues/9)
* **carmack:** run carmack from neurogenomics/carmack's published image ([6e3e43b](https://github.com/neurogenomics/jacquard/commit/6e3e43b5ba6240b054da33ba23ef2756916ac8b0))
* **carmack:** run carmack from neurogenomics/carmack's published image ([#49](https://github.com/neurogenomics/jacquard/issues/49)) ([9cd96a7](https://github.com/neurogenomics/jacquard/commit/9cd96a7c13e74ff01293969cdf4a9076c6e1a5b3))
* core skeleton — carmack read prep, gated arm fan-out, alignment ([3c58a74](https://github.com/neurogenomics/jacquard/commit/3c58a74c516b2dad4fbfb4b53be30d9384f1be9f))
* **input:** merge a sample's flowcell lanes before read prep ([68345de](https://github.com/neurogenomics/jacquard/commit/68345de7ed251032e701751e1dda9d70a69c0377))
* **input:** merge a sample's flowcell lanes before read prep ([#35](https://github.com/neurogenomics/jacquard/issues/35)) ([81b6463](https://github.com/neurogenomics/jacquard/commit/81b646374c66c747efeb949ea54a8880caf6c86f))
* **lineardedup:** add the carmack linear-dedup module ([ab5d214](https://github.com/neurogenomics/jacquard/commit/ab5d214f0e240297d0df9f173b55df55d97be62d)), closes [#21](https://github.com/neurogenomics/jacquard/issues/21)
* require fastq_2 and add the SK609 test fixtures ([8c87c29](https://github.com/neurogenomics/jacquard/commit/8c87c2960070a219fd421b0e78d993ba1ffda0aa)), closes [#2](https://github.com/neurogenomics/jacquard/issues/2)
* **scrna:** expose STARsolo multimappers and an optional tagged BAM ([#30](https://github.com/neurogenomics/jacquard/issues/30), [#31](https://github.com/neurogenomics/jacquard/issues/31)) ([751beac](https://github.com/neurogenomics/jacquard/commit/751beacb0e3cbf161518aa820b9782505fb2b411))
* **scrna:** paired forward-stranded STARsolo counting, multimapper option and a tagged BAM ([f650edd](https://github.com/neurogenomics/jacquard/commit/f650eddebdc71404aadfa90e95de86fe7d748675))
* **sctip:** run linear deduplication behind --skip_linear_dedup ([18be204](https://github.com/neurogenomics/jacquard/commit/18be2047c44f9ae11ae89976611720ef2df1685d)), closes [#22](https://github.com/neurogenomics/jacquard/issues/22)
* **sctip:** single-cell linear deduplication for the scTIP arm ([5a2a25d](https://github.com/neurogenomics/jacquard/commit/5a2a25d203fc6cdd0ec1d3fe45138e723c604c50))
* trim the scRNA arm with fastp and resync its barcode read ([855fd6d](https://github.com/neurogenomics/jacquard/commit/855fd6d12021e06a81c07def623a3f91a947920b)), closes [#15](https://github.com/neurogenomics/jacquard/issues/15)
* trim the scTIP arm with fastp before alignment ([e7d535f](https://github.com/neurogenomics/jacquard/commit/e7d535f2e58c030df9705e97e3e5f03ac2b8f4b1)), closes [#14](https://github.com/neurogenomics/jacquard/issues/14)


### Fixed

* bump carmack to ffa5349 and resync the nf-test fixtures ([5e52f8e](https://github.com/neurogenomics/jacquard/commit/5e52f8e754de0fc29aa2ab1f7c08890796b85f85)), closes [#17](https://github.com/neurogenomics/jacquard/issues/17)
* **carmack:** pin the image to the submodule's sha tag ([#49](https://github.com/neurogenomics/jacquard/issues/49)) ([93a00c6](https://github.com/neurogenomics/jacquard/commit/93a00c621ca81da23cb9bf15cb5c3c01b11941a2))
* close the gaps a whole-epic review found ([cc5b8e8](https://github.com/neurogenomics/jacquard/commit/cc5b8e8cfd15b4c31cab8037ad3a3a9752486aa0))
* **fastp:** lower the scTIP length floor to 20 and hide the insert-size plot ([153ecb5](https://github.com/neurogenomics/jacquard/commit/153ecb5e302bb91aa52ea61b5b14dc7e80f0dcb8))
* **input:** reject a FASTQ listed on two rows and log each lane merge ([c55d4b5](https://github.com/neurogenomics/jacquard/commit/c55d4b5c1cf7100c8a2dfb2a38bb28052b8ad5b9)), closes [#35](https://github.com/neurogenomics/jacquard/issues/35)
* **multiqc:** hide fastp's insert-size plot ([#42](https://github.com/neurogenomics/jacquard/issues/42)) ([6d99fe4](https://github.com/neurogenomics/jacquard/commit/6d99fe419aac71c31a05b5ca59e9587fd583e94c))
* **scrna:** count the scRNA arm forward-stranded ([#37](https://github.com/neurogenomics/jacquard/issues/37)) ([70e9586](https://github.com/neurogenomics/jacquard/commit/70e9586a97a771933366917d32ea3ce7a7d90252))
* **scrna:** count unstranded reads with --soloStrand Unstranded ([#29](https://github.com/neurogenomics/jacquard/issues/29)) ([751beac](https://github.com/neurogenomics/jacquard/commit/751beacb0e3cbf161518aa820b9782505fb2b411)), closes [#30](https://github.com/neurogenomics/jacquard/issues/30) [#31](https://github.com/neurogenomics/jacquard/issues/31)
* **scrna:** map both cDNA mates in STARsolo ([#38](https://github.com/neurogenomics/jacquard/issues/38)) ([94376f0](https://github.com/neurogenomics/jacquard/commit/94376f068f22c140160b32844796ab270cc885de))
* **sctip:** keep bowtie2's output in input order ([#46](https://github.com/neurogenomics/jacquard/issues/46)) ([0dd1b4a](https://github.com/neurogenomics/jacquard/commit/0dd1b4aea2eb1f5dce23c9b2edb3e7abe96d5e34))
* **sctip:** lower fastp's length floor from 25 to 20 ([#41](https://github.com/neurogenomics/jacquard/issues/41)) ([8dd8112](https://github.com/neurogenomics/jacquard/commit/8dd8112d5825efd827c711d1f58a21420563d576))
* **sctip:** set bowtie2's alignment options and expose --min_mapq ([69061b5](https://github.com/neurogenomics/jacquard/commit/69061b5a41f2386d6702e388ea40b2ecba293a1c))


### Changed

* **carmack:** bump to 01f2d18, bounding linear dedup's memory by chromosome ([b0116c7](https://github.com/neurogenomics/jacquard/commit/b0116c7d7ef09ad5bba39b838f8ed6dc76f25fa0)), closes [#20](https://github.com/neurogenomics/jacquard/issues/20)


### Documentation

* flag the pipeline as incomplete and under development ([c59988d](https://github.com/neurogenomics/jacquard/commit/c59988dedef1d4bf0564bbdccfa4ab5eab8ae838))

## Changelog

All notable changes to neurogenomics/jacquard are documented here.

This file is maintained by [release-please](https://github.com/googleapis/release-please) from
[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/); do not edit it by hand.
