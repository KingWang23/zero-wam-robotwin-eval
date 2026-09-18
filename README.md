# Zero-WAM + RoboTwin 可迁移评测环境

这是一个面向复现实验的源码快照，包含：

- Zero-WAM `08e2c4ae41e2b63573a299825cebe6753481407c` 及本地评测修改。
- RoboTwin `2eeec322d95799f537cbfe5f291a8220d965ccb8` 及两个任务成功条件修改。
- 单任务、7 任务串行、双 GPU 并行、ICL/no-ICL 公平对照脚本。
- CPU/GPU VAE、Imagined Video、prompt manifest 重放支持。
- Conda 环境、依赖安装、资源下载和安装检查脚本。

上游项目及许可证见 [UPSTREAM.md](UPSTREAM.md)。本仓库不改变上游代码的许可证。

## 未包含内容

以下内容体积较大，不提交到 GitHub：

- Zero-WAM checkpoint。
- HumanGen 数据与 ICL latent。
- RoboTwin assets 和预采集数据集。
- 评测结果、视频、日志和缓存。

它们可以通过 `scripts/download_runtime.sh` 下载。

## 1. 克隆

```bash
git clone git@github.com:KingWang23/zero-wam-robotwin-eval.git
cd zero-wam-robotwin-eval
```

目录必须保持为：

```text
zero-wam-robotwin-eval/
├── Zero-WAM/
├── RoboTwin/
├── configs/
├── environments/
└── scripts/
```

## 2. 系统要求

- Linux x86_64
- NVIDIA GPU 与可用驱动
- Conda/Miniconda
- Git、Git LFS、编译工具、Ninja 和 unzip
- 建议每张 GPU 至少 48 GB；较小显存请使用服务端/模拟器分卡模式

Ubuntu 可先安装：

```bash
sudo apt-get update
sudo apt-get install -y git git-lfs build-essential ninja-build unzip
```

## 3. 创建环境

```bash
bash scripts/bootstrap_envs.sh
```

该脚本创建：

- `zerowam`：Python 3.10 与 Zero-WAM 依赖。
- `RoboTwin`：Python 3.10、CUDA Toolkit 12.1 与 RoboTwin/Curobo 依赖。

Curobo 固定到已验证提交 `d64c4b005459db10c5dd867d8b30a87d5bda9bdb`。

## 4. 下载运行资源

下载 RoboTwin assets、Robotwin posttrain checkpoint 和最小 ICL latent：

```bash
bash scripts/download_runtime.sh all
```

也可以分开下载：

```bash
bash scripts/download_runtime.sh assets
bash scripts/download_runtime.sh checkpoint
bash scripts/download_runtime.sh icl
```

## 5. 检查安装

静态检查：

```bash
bash scripts/verify_install.sh
```

包含 SAPIEN GPU 渲染检查：

```bash
bash scripts/verify_install.sh --render
```

## 6. 快速烟雾测试

```bash
cd Zero-WAM

GPU_IDS=0,1 \
VAE_DEVICE=cpu \
TEST_NUM=1 \
MAX_STEPS=16 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_two_gpu_eval.sh icl
```

## 7. ICL/no-ICL 公平对照

仓库提供 7 个任务、每个任务 20 个 episode 的 prompt manifest：

```bash
cd Zero-WAM

GPU_IDS=0,1 \
VAE_DEVICE=cpu \
SEED=0 \
TEST_NUM=20 \
MAX_STEPS=0 \
PROMPT_MANIFEST=../configs/fair_eval_prompts_20.json \
SAVE_ROOT="$PWD/results/fair_icl_vs_no_icl_20" \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_two_gpu_eval.sh both
```

结果分别写入 `results/fair_icl_vs_no_icl_20/icl` 和 `no_icl`。详细参数与故障排查见 [Zero-WAM/ROBOTWIN_EVAL_ZH.md](Zero-WAM/ROBOTWIN_EVAL_ZH.md)。

## 8. 重要说明

- 首次安装和下载需要较长时间与充足磁盘空间。
- `VAE_DEVICE=cpu` 显存较低但视频编解码更慢；`gpu` 更快但更容易 OOM。
- 本快照针对 RoboTwin `2eeec322` 验证，不建议在首次复现前升级依赖或切换 RoboTwin 提交。
- 公开仓库只包含源码和配置，不包含本机凭据或 Hugging Face/GitHub token。
