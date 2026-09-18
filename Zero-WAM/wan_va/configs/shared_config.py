# Copyright 2024-2025 The Robbyant Team Authors. All rights reserved.
import os

import torch
from easydict import EasyDict

va_shared_cfg = EasyDict()

va_shared_cfg.host = '0.0.0.0'
va_shared_cfg.port = 29536
va_shared_cfg.infer_mode = 'server'

va_shared_cfg.param_dtype = torch.bfloat16
va_shared_cfg.save_root = './train_out'

va_shared_cfg.patch_size = (1, 2, 2)

va_shared_cfg.enable_offload = os.environ.get(
    "ZERO_WAM_ENABLE_OFFLOAD", "0"
).lower() in {"1", "true", "yes", "on"}

_default_vae_device = "cpu" if va_shared_cfg.enable_offload else "cuda"
_vae_device = os.environ.get(
    "ZERO_WAM_VAE_DEVICE", _default_vae_device
).strip().lower()
if _vae_device == "gpu":
    _vae_device = "cuda"
if _vae_device not in {"cpu", "cuda"}:
    raise ValueError(
        "ZERO_WAM_VAE_DEVICE must be 'cpu', 'gpu', or 'cuda', "
        f"got {_vae_device!r}"
    )
va_shared_cfg.vae_device = _vae_device

# Cache the validated latent sample index so repeated training runs do not scan
# every latent path on network storage again.
va_shared_cfg.enable_dataset_index_cache = True
va_shared_cfg.rebuild_dataset_index_cache = False
