# Zero-WAM 在 RoboTwin 2.0 上的评测启动指南

本文档说明如何在当前工作目录中启动 Zero-WAM 的 RoboTwin 2.0 评测，包括：

- Human Video ICL 评测
- 不使用 ICL、仅使用语言指令的对照评测
- Real Observation 与 Imagined Video Stream 可视化
- 单任务快速测试和正式评测
- 双 GPU 分配、CPU offload 和常见问题排查

## 1. 当前目录与版本

本文档按照以下目录布局编写：

```text
/path/to/zero-wam-robotwin-eval/
├── Zero-WAM/
└── RoboTwin/
```

当前评测使用：

```text
Zero-WAM 环境：zerowam
RoboTwin 环境：RoboTwin
RoboTwin commit：2eeec322
Zero-WAM checkpoint：checkpoints/zero-wam-posttrain-robotwin
```

迁移仓库中的 RoboTwin 源码快照基于 `2eeec322`，版本信息见顶层
`UPSTREAM.md`。不要直接用最新 `main` 覆盖该目录，因为新版本的目录结构可能与
Zero-WAM 客户端不兼容。

## 2. 启动前检查

### 2.1 检查 Conda 环境

```bash
conda env list
```

应当同时存在：

```text
zerowam
RoboTwin
```

检查核心依赖：

```bash
conda run -n zerowam python -c \
  "import torch; print(torch.__version__, torch.version.cuda)"

conda run -n RoboTwin python -c \
  "import torch, sapien, curobo; print(torch.__version__, torch.version.cuda)"
```

当前已验证的主要版本为：

```text
zerowam：PyTorch 2.9.0 + CUDA 12.6
RoboTwin：PyTorch 2.4.1 + CUDA 12.1
Curobo：v0.7.8，本地 editable 安装
```

服务端和模拟器使用不同 Conda 环境是正常的，它们通过本机 WebSocket 通信。

### 2.2 检查 checkpoint

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM

test -f checkpoints/zero-wam-posttrain-robotwin/transformer/config.json
test -f checkpoints/zero-wam-posttrain-robotwin/vae/config.json
test -f checkpoints/zero-wam-posttrain-robotwin/text_encoder/config.json
```

checkpoint 目录约为 35 GB：

```bash
du -sh checkpoints/zero-wam-posttrain-robotwin
```

### 2.3 检查 Human Video ICL latent

带 ICL 评测默认使用预计算 latent，不需要在线编码 Human Video：

```bash
find data/HumanGen/human_latents/robotwin -type f -name '*.pth' | head
```

固定 Human Video 映射位于：

```text
evaluation/robotwin/robotwin_icl_human_videos.py
```

### 2.4 检查 GPU

```bash
nvidia-smi
```

Zero-WAM 服务端需要大量显存。当前机器还有其他 GPU 进程，因此推荐：

```text
GPU 1：Zero-WAM 推理服务
GPU 0：RoboTwin、SAPIEN 和 Curobo
CPU：VAE 与 text encoder
```

不要在当前机器上把服务端和模拟器都放在同一张卡，否则容易在 VAE 编码或 KV cache 增长时 OOM。

## 3. 推荐的一键启动方式

所有命令都从 Zero-WAM 根目录执行：

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM
```

一键脚本会自动完成：

- 选择 `zerowam` 和 `RoboTwin` Conda 环境
- 启动 Zero-WAM 服务
- 等待 `/healthz` 就绪
- 启动 RoboTwin rollout
- 保存指标和对比视频
- 结束后清理服务端及其子进程

### 3.1 带 Human Video ICL 的正式评测

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_with_icl.sh place_object_scale
```

该模式自动设置：

```text
USE_ICL=1
ICL_CFG=5
TARGET_TEXT_CFG=-1
SAVE_ROOT=results/icl
```

含义：

- 使用固定 Human Video ICL latent。
- `ICL_CFG=5` 在带 ICL 与不带 ICL 的 robot-video 分支之间做 classifier-free guidance。
- `TARGET_TEXT_CFG=-1` 对目标机器人流使用 empty-text embedding，符合 Zero-WAM 发布的 ICL 协议。

### 3.2 不带 ICL、仅语言条件的正式评测

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_without_icl.sh place_object_scale
```

该模式自动设置：

```text
USE_ICL=0
ICL_CFG=1
TARGET_TEXT_CFG=1
SAVE_ROOT=results/no_icl
```

`TARGET_TEXT_CFG=1` 表示使用任务语言指令，但不做额外 target-text CFG。不要在 no-ICL 对照中使用 `TARGET_TEXT_CFG=-1`，否则模型既没有 Human Video ICL，也没有目标文本条件。

### 3.3 快速烟雾测试

在正式跑 100 次之前，建议先执行 16 步短测：

带 ICL：

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=1 \
MAX_STEPS=16 \
SAVE_IMAGINED_VIDEO=1 \
SAVE_ROOT=/path/to/zero-wam-robotwin-eval/Zero-WAM/results/smoke_icl \
bash evaluation/robotwin/run_with_icl.sh place_object_scale
```

不带 ICL：

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=1 \
MAX_STEPS=16 \
SAVE_IMAGINED_VIDEO=1 \
SAVE_ROOT=/path/to/zero-wam-robotwin-eval/Zero-WAM/results/smoke_no_icl \
bash evaluation/robotwin/run_without_icl.sh place_object_scale
```

`MAX_STEPS` 只用于功能检查。正式评测必须不设置该变量，或者设置为 `0`。

## 4. 可评测任务

Zero-WAM 发布协议中的七个 unseen tasks 为：

```text
place_object_scale
stamp_seal
open_microwave
move_stapler_pad
place_bread_basket
place_empty_cup
stack_blocks_three
```

将脚本最后一个参数替换为任务名即可，例如：

```bash
SERVER_GPU_ID=1 CLIENT_GPU_ID=0 TEST_NUM=100 SEED=0 \
bash evaluation/robotwin/run_with_icl.sh place_bread_basket
```

`move_stapler_pad` 和 `stamp_seal` 已应用 Zero-WAM 论文使用的成功条件更新。

### 4.1 依次运行全部七个任务

批量脚本会严格串行执行任务：当前任务退出并清理服务端后，才会启动下一个任务；某个任务失败时会记录失败状态并继续，最后统一汇总。

先进入 Zero-WAM 根目录：

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM
```

依次运行七个带 ICL 的任务：

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_all_tasks.sh icl
```

依次运行七个不带 ICL 的任务：

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_all_tasks.sh no_icl
```

先跑完带 ICL，再跑完不带 ICL，共执行十四组评测：

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_all_tasks.sh both
```

正式评测前，建议先对全部任务执行一次 16 步短测：

```bash
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=1 \
MAX_STEPS=16 \
SAVE_IMAGINED_VIDEO=1 \
SAVE_ROOT=/path/to/zero-wam-robotwin-eval/Zero-WAM/results/smoke_all \
bash evaluation/robotwin/run_all_tasks.sh both
```

使用 `both` 时，如果设置了 `SAVE_ROOT`，结果会分别写入其 `icl/` 和 `no_icl/` 子目录。未设置时默认写入 `results/icl/` 与 `results/no_icl/`。服务端日志仍按任务和启动时间保存在 `logs/` 下。

### 4.2 两张 GPU 并行运行全部任务

`run_two_gpu_eval.sh` 会启动两个常驻 worker：

```text
worker 0：GPU 0 上同时运行 Zero-WAM 服务和 RoboTwin 模拟器
worker 1：GPU 1 上同时运行 Zero-WAM 服务和 RoboTwin 模拟器
```

七个任务会交错分配给两个 worker。每张卡上的 Zero-WAM 只加载一次，随后依次处理分配给该卡的任务。使用 `both` 时，同一个任务在 ICL 和 no-ICL 阶段固定到同一张 GPU，避免硬件映射成为额外变量。

先进行两卡 16 步短测，VAE 放在 CPU：

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM

GPU_IDS=0,1 \
VAE_DEVICE=cpu \
TEST_NUM=1 \
MAX_STEPS=16 \
SAVE_IMAGINED_VIDEO=1 \
SAVE_ROOT=/path/to/zero-wam-robotwin-eval/Zero-WAM/results/smoke_two_gpu \
bash evaluation/robotwin/run_two_gpu_eval.sh both
```

正式并行运行七个带 ICL 的任务：

```bash
GPU_IDS=0,1 \
VAE_DEVICE=cpu \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_two_gpu_eval.sh icl
```

正式并行运行七个 no-ICL 任务：

```bash
GPU_IDS=0,1 \
VAE_DEVICE=cpu \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_two_gpu_eval.sh no_icl
```

依次完成带 ICL 和 no-ICL，共十四组评测：

```bash
GPU_IDS=0,1 \
VAE_DEVICE=cpu \
TEST_NUM=100 \
SEED=0 \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_two_gpu_eval.sh both
```

两个服务默认使用端口 `29056/29057` 和 distributed 端口 `29061/29062`。客户端和服务端日志分别写入 `logs/client_two_gpu_*` 和 `logs/server_two_gpu_*`。按 `Ctrl-C` 会停止两个 worker 和两个服务端。

默认运行全部七个任务。调试或断点补跑时，可以用逗号分隔的 `TASK_NAMES` 指定任务子集，例如：

```bash
GPU_IDS=0,1 \
TASK_NAMES=place_object_scale,stamp_seal \
VAE_DEVICE=cpu \
TEST_NUM=1 MAX_STEPS=16 \
bash evaluation/robotwin/run_two_gpu_eval.sh icl
```

两卡并行模式要求每张卡能同时容纳 Zero-WAM Transformer、RoboTwin/SAPIEN/Curobo 以及运行缓存。优先使用 `VAE_DEVICE=cpu`；若仍然 OOM，应改用前文的 `SERVER_GPU_ID`/`CLIENT_GPU_ID` 分卡单任务模式。

### 4.3 与历史 ICL 结果严格配对

旧版指令生成器没有固定 Python `random`，所以只设置相同 `SEED` 不能保证历史 ICL 与新 no-ICL 使用相同措辞。当前客户端已对未来运行固定 instruction RNG；要匹配已经生成的旧 ICL，必须使用 prompt manifest 重放历史 prompt。

从历史 ICL 视频名称生成清单：

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM

python evaluation/robotwin/build_prompt_manifest.py \
  results/icl/stseed-100000/visualization \
  results/icl/stseed-100000/prompt_manifest.json
```

当前历史结果包含每个任务 20 个 episode，因此用相同 `SEED=0`、`TEST_NUM=20` 从 episode 0 重新运行 no-ICL，并写入新目录：

```bash
GPU_IDS=0,1 \
VAE_DEVICE=cpu \
SEED=0 \
TEST_NUM=20 \
PROMPT_MANIFEST=/path/to/zero-wam-robotwin-eval/configs/fair_eval_prompts_20.json \
SAVE_ROOT=/path/to/zero-wam-robotwin-eval/Zero-WAM/results/no_icl_paired \
SAVE_IMAGINED_VIDEO=1 \
bash evaluation/robotwin/run_two_gpu_eval.sh no_icl
```

不要把配对结果继续写入已有的 `results/no_icl`，因为其中已经存在使用其他随机 prompt 的 episode。manifest 缺少某个任务或 episode 时，客户端会直接报错，不会静默生成新 prompt。视频名中的 episode 编号和 prompt 应与历史 ICL 一致，末尾的 `True/False` 可以不同，因为它表示该策略 rollout 是否成功。

### 4.4 全新公平重测 ICL 与 no-ICL

推荐在同一次 `both` 启动中重测两种模式，并让它们共用同一份 prompt manifest。当前 manifest 每个任务包含 20 个 episode，因此这里必须设置 `TEST_NUM=20`：

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM

GPU_IDS=0,1 \
VAE_DEVICE=cpu \
ZERO_WAM_ENABLE_OFFLOAD=1 \
SEED=0 \
TEST_NUM=20 \
MAX_STEPS=0 \
PROMPT_MANIFEST=/path/to/zero-wam-robotwin-eval/configs/fair_eval_prompts_20.json \
SAVE_ROOT=/path/to/zero-wam-robotwin-eval/Zero-WAM/results/fair_icl_vs_no_icl_20 \
SAVE_IMAGINED_VIDEO=1 \
ICL_GUIDANCE_SCALE=5 \
ICL_TEXT_GUIDANCE_SCALE=-1 \
NO_ICL_GUIDANCE_SCALE=1 \
NO_ICL_TEXT_GUIDANCE_SCALE=1 \
bash evaluation/robotwin/run_two_gpu_eval.sh both
```

输出会自动分开：

```text
results/fair_icl_vs_no_icl_20/icl
results/fair_icl_vs_no_icl_20/no_icl
```

该命令保证两种模式使用相同任务、episode 编号、RoboTwin seed、target prompt、任务配置、最大步数、VAE 设备和 GPU 映射。同一个任务在两种模式下固定到同一张 GPU。实验变量只保留是否启用 Human Video ICL 及论文协议对应的 guidance 设置。

正式比较时不要设置正数 `MAX_STEPS`；`MAX_STEPS=0` 表示使用任务原始步数。运行后可搜索 `[PROMPT] replay` 检查 prompt 重放，并比较两边视频名：除末尾表示结果的 `True/False` 外，同一 episode 的名称应一致。

## 5. Imagined Video Stream

默认开启 predicted latent 的 VAE 解码：

```bash
SAVE_IMAGINED_VIDEO=1
```

输出视频包含上下两部分：

```text
上方：Real Observation (High / Left / Right)
下方：Imagined Video Stream
```

如果只关心成功率、不需要 Imagined Video，可以关闭解码以提高速度：

```bash
SAVE_IMAGINED_VIDEO=0 \
SERVER_GPU_ID=1 \
CLIENT_GPU_ID=0 \
TEST_NUM=100 \
bash evaluation/robotwin/run_with_icl.sh place_object_scale
```

`VAE_DEVICE=cpu` 时，Imagined Video 由 CPU VAE 解码，因此每个 action chunk 会明显变慢。这是正常现象。

## 6. 显存与 CPU offload

一键脚本默认设置：

```text
ZERO_WAM_ENABLE_OFFLOAD=1
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
```

`ZERO_WAM_ENABLE_OFFLOAD=1` 会将 text encoder 放在 CPU，并让 VAE 默认位于 CPU；主要 Transformer 始终位于服务端 GPU。现在可以通过 `VAE_DEVICE` 单独覆盖 VAE 的位置。

VAE 在 CPU 上进行 observation 编码和 Imagined Video 解码，显存占用较低：

```bash
VAE_DEVICE=cpu \
SERVER_GPU_ID=1 CLIENT_GPU_ID=0 \
bash evaluation/robotwin/run_with_icl.sh place_object_scale
```

VAE 在 GPU 上编解码，速度更快，但占用更多显存：

```bash
VAE_DEVICE=gpu \
SERVER_GPU_ID=1 CLIENT_GPU_ID=0 \
bash evaluation/robotwin/run_with_icl.sh place_object_scale
```

`VAE_DEVICE` 只控制 VAE。`ZERO_WAM_ENABLE_OFFLOAD=1` 仍可同时保留，使 text encoder 留在 CPU。两卡并行运行模拟器和模型时，推荐 `VAE_DEVICE=cpu`。

如果使用独占的大显存 GPU，可关闭 offload：

```bash
ZERO_WAM_ENABLE_OFFLOAD=0 \
SERVER_GPU_ID=0 \
CLIENT_GPU_ID=1 \
TEST_NUM=100 \
bash evaluation/robotwin/run_with_icl.sh place_object_scale
```

未显式设置 `VAE_DEVICE` 时，关闭 offload 也会让 VAE 默认进入 GPU，从而加速编解码，但会增加数 GB 显存占用。显式设置的 `VAE_DEVICE` 始终优先。

Zero-WAM 的 observation KV cache 会随 action chunk 增长。当前 `attn_window=64`，而一个 400 步 episode 约有 13 个 chunk，因此同一局内通常还不会触发窗口裁剪。显存随 rollout 上升是预期行为，不一定是内存泄漏。

## 7. 输出位置

### 7.1 带 ICL

```text
results/icl/stseed-<起始种子>/metrics/<任务名>/res.json
results/icl/stseed-<起始种子>/visualization/<任务名>/*.mp4
```

### 7.2 不带 ICL

```text
results/no_icl/stseed-<起始种子>/metrics/<任务名>/res.json
results/no_icl/stseed-<起始种子>/visualization/<任务名>/*.mp4
```

指标文件示例：

```json
{
    "succ_num": 0.0,
    "total_num": 1.0,
    "succ_rate": 0.0
}
```

服务日志保存在：

```text
logs/server_single_<任务名>_<时间>.log
```

查看最新日志：

```bash
ls -lt logs/server_single_*.log | head
tail -f logs/server_single_place_object_scale_*.log
```

## 8. 常用环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SERVER_GPU_ID` | `GPU_ID` 或 `0` | Zero-WAM 服务使用的物理 GPU |
| `CLIENT_GPU_ID` | `GPU_ID` 或 `0` | RoboTwin、SAPIEN、Curobo 使用的物理 GPU |
| `TEST_NUM` | `1` | 正式评测建议设置为 `100` |
| `SEED` | `0` | RoboTwin rollout seed 组编号 |
| `MAX_STEPS` | `0` | `0` 表示官方任务步数；短测可设为 `16` |
| `SAVE_IMAGINED_VIDEO` | `1` | 是否解码并保存 Imagined Video Stream |
| `VAE_DEVICE` | `cpu` | VAE 编码和解码设备，可设为 `cpu` 或 `gpu` |
| `ZERO_WAM_ENABLE_OFFLOAD` | `1` | 是否 offload text encoder，并决定未设置 `VAE_DEVICE` 时的 VAE 默认位置 |
| `GPU_IDS` | `0,1` | 两卡并行脚本使用的两个物理 GPU |
| `TASK_NAMES` | 全部七个任务 | 两卡并行脚本的任务子集，使用逗号分隔 |
| `PROMPT_MANIFEST` | 空 | 按任务和 episode 重放历史 prompt 的 JSON 文件 |
| `START_PORT` | `29056` | 两卡并行服务端口起点，实际使用该端口及下一个端口 |
| `START_MASTER_PORT` | `29061` | 两卡并行 distributed 端口起点 |
| `SAVE_ROOT` | 按模式自动选择 | 指标和视频输出目录 |
| `MODEL_PATH` | 发布的 posttrain checkpoint | Zero-WAM 模型目录 |
| `ROBOTWIN_ROOT` | 相邻的 `../RoboTwin` | RoboTwin checkout 路径 |
| `PORT` | `29056` | WebSocket 服务端口 |
| `MASTER_PORT` | `29061` | Torch distributed rendezvous 端口 |
| `SERVER_START_TIMEOUT` | `900` | 模型服务启动超时，单位为秒 |
| `ICL_SEED` | 跟随 `SEED` | 固定 Human Video 选择 |

## 9. 双终端手动启动

一般推荐使用一键脚本。需要调试服务端和客户端时，可以分别启动。

### 9.1 终端一：启动 Zero-WAM 服务

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM

CUDA_VISIBLE_DEVICES=1 \
MODEL_PATH=/path/to/zero-wam-robotwin-eval/Zero-WAM/checkpoints/zero-wam-posttrain-robotwin \
PORT=29056 \
MASTER_PORT=29061 \
ZERO_WAM_ENABLE_OFFLOAD=1 \
ZERO_WAM_VAE_DEVICE=cpu \
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
conda run --no-capture-output -n zerowam \
bash evaluation/robotwin/launch_server.sh
```

检查服务：

```bash
curl http://127.0.0.1:29056/healthz
```

预期输出：

```text
OK
```

### 9.2 终端二：启动带 ICL 客户端

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM

CUDA_VISIBLE_DEVICES=0 \
ROBOTWIN_ROOT=/path/to/zero-wam-robotwin-eval/RoboTwin \
PORT=29056 \
TEST_NUM=100 \
SEED=0 \
USE_ICL=1 \
ICL_CFG=5 \
TARGET_TEXT_CFG=-1 \
SAVE_IMAGINED_VIDEO=1 \
conda run --no-capture-output -n RoboTwin \
bash evaluation/robotwin/launch_client.sh \
  /path/to/zero-wam-robotwin-eval/Zero-WAM/results/icl \
  place_object_scale
```

### 9.3 终端二：启动 no-ICL 客户端

```bash
cd /path/to/zero-wam-robotwin-eval/Zero-WAM

CUDA_VISIBLE_DEVICES=0 \
ROBOTWIN_ROOT=/path/to/zero-wam-robotwin-eval/RoboTwin \
PORT=29056 \
TEST_NUM=100 \
SEED=0 \
USE_ICL=0 \
ICL_CFG=1 \
TARGET_TEXT_CFG=1 \
SAVE_IMAGINED_VIDEO=1 \
conda run --no-capture-output -n RoboTwin \
bash evaluation/robotwin/launch_client.sh \
  /path/to/zero-wam-robotwin-eval/Zero-WAM/results/no_icl \
  place_object_scale
```

手动方式结束后，需要在终端一按 `Ctrl-C` 停止服务。使用一键脚本时会自动清理。

## 10. 常见问题

### 10.1 CUDA out of memory

首先检查：

```bash
nvidia-smi
```

推荐处理顺序：

1. 将服务端和客户端放到不同 GPU。
2. 保持 `ZERO_WAM_ENABLE_OFFLOAD=1`。
3. 保持 `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`。
4. 关闭 Imagined Video 解码：`SAVE_IMAGINED_VIDEO=0`。
5. 等待其他 GPU 任务结束，不要直接终止未知进程。

### 10.2 `No module named curobo`

当前环境已经安装。如果重新创建了 RoboTwin 环境，推荐在迁移仓库根目录重新运行：

```bash
cd /path/to/zero-wam-robotwin-eval
bash scripts/bootstrap_envs.sh
```

系统 `/usr/local/cuda` 当前可能指向 CUDA 11.8，而 RoboTwin PyTorch 使用 CUDA 12.1，因此必须显式设置 `CUDA_HOME`。

### 10.3 `Render Error`

检查 GPU、Vulkan 和 SAPIEN：

```bash
CUDA_VISIBLE_DEVICES=0 conda run -n RoboTwin \
python /path/to/zero-wam-robotwin-eval/Zero-WAM/evaluation/robotwin/test_render.py
```

正常时应输出：

```text
Render Well
```

### 10.4 端口已被占用

一键脚本会报：

```text
Port 29056 already has a Zero-WAM server
```

可以换端口：

```bash
PORT=29156 MASTER_PORT=29161 \
SERVER_GPU_ID=1 CLIENT_GPU_ID=0 \
bash evaluation/robotwin/run_with_icl.sh place_object_scale
```

### 10.5 客户端一直等待服务

先检查：

```bash
curl http://127.0.0.1:29056/healthz
tail -100 logs/server_single_*.log
```

客户端已固定连接 `127.0.0.1` 并禁用本地 WebSocket 代理，因此不会再被 `HTTP_PROXY` 或 `HTTPS_PROXY` 转发。

### 10.6 视频中没有 Imagined Video Stream

确认启动命令包含：

```bash
SAVE_IMAGINED_VIDEO=1
```

正常保存时终端会显示类似：

```text
Saving video: Real 5 frames, Imagined 5 frames...
```

如果显示 `Imagined 0 frames`，检查服务日志中是否存在 VAE decode 异常。

### 10.7 评测结果为 Fail

单次 `Fail` 不代表环境配置失败。只要满足以下条件，评测链路就是正常的：

- SAPIEN 输出 `Render Well`
- 服务端完成 WebSocket 握手
- 客户端持续输出 `step: x / 400`
- 最终生成 `res.json` 和 MP4

正式成功率需要按论文协议运行 `TEST_NUM=100`，不要用一次 rollout 判断模型整体效果。

## 11. 推荐执行顺序

1. 执行带 ICL 的 16 步烟雾测试。
2. 执行 no-ICL 的 16 步烟雾测试。
3. 检查两边视频都包含 Real 和 Imagined Stream。
4. 去掉 `MAX_STEPS`，将 `TEST_NUM` 改为 `100`。
5. 对七个 unseen tasks 分别运行并保存到独立结果目录。
