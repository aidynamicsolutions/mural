#!/usr/bin/env python3
"""Run in the isolated compression venv; tiny graph, no PhoWhisper inference."""
import tempfile
from pathlib import Path
import torch
from coreai.authoring import AIModelAsset
from coreai_torch import TorchConverter, get_decomp_table
from coreai_opt.coreai_utils import quantize_weights, DType, CompressionGranularity
from coreai_opt.coreai_utils.common import QScheme
from compress_phowhisper_encoder import audit, fingerprint, totals

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    model = torch.nn.Linear(64, 64).half().eval()
    exported = torch.export.export(model, (torch.zeros(1, 64, dtype=torch.float16),))
    program = TorchConverter(mode=TorchConverter.Mode.RELEASE).add_exported_program(
        exported_program=exported.run_decompositions(get_decomp_table()),
        input_names=["x"], output_names=["y"]).to_coreai()
    original = audit(program)
    eligible = [r for r in original["constants"] if r["eligible"]]
    assert totals(eligible) == {"tensors": 1, "elements": 4096, "source_precision_bytes": 8192}
    for dtype in (DType.FP8_E4M3FN, DType.INT8):
        compressed = quantize_weights(program, dtype=dtype, qscheme=QScheme.SYMMETRIC,
            granularity=CompressionGranularity.PER_CHANNEL, scale_dtype=None, in_place=False)
        path = root / (dtype.value + ".aimodel")
        compressed.save_asset(path)
        result = audit(AIModelAsset.load(path).program)
        assert totals(result["compressed_weights"]) == totals(eligible)
        assert result["operations"]["coreai.blockwise_shift_scale"] == 1
        assert not any(r["eligible"] for r in result["constants"])
        assert audit(program) == original, "in_place=False changed the source graph"
        digest = fingerprint(path)
        (path / "extra").write_text("changed")
        assert fingerprint(path) != digest
    link = root / "link"
    link.symlink_to(path, target_is_directory=True)
    try:
        fingerprint(link)
    except ValueError:
        pass
    else:
        raise AssertionError("Symlink accepted")
print("PASS: FP8/INT8 saved compression ops, coverage, unchanged source, fingerprints")
