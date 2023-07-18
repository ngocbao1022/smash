from __future__ import annotations

from smash._constant import COMPUTE_BY

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from smash._typing import AnyTuple


def _standardize_hydrograph_segmentation_peak_quant(peak_quant: float) -> float:
    if not isinstance(peak_quant, float):
        raise TypeError("peak_quant argument must be float")

    elif peak_quant <= 0 or peak_quant >= 1:
        raise ValueError("peak_quant argument must be between 0 and 1")

    return float(peak_quant)


def _standardize_hydrograph_segmentation_max_duration(
    max_duration: int | float,
) -> float:
    if not isinstance(max_duration, (int, float)):
        raise TypeError("max_duration argument must be of Numeric type (int, float)")

    max_duration = float(max_duration)

    if max_duration <= 0:
        raise ValueError("max_duration argument must be greater than 0")

    return max_duration


def _standardize_hydrograph_segmentation_by(by: str) -> str:
    if isinstance(by, str):
        by_standardized = by.lower()

        if by_standardized in COMPUTE_BY:
            by_standardized = by_standardized[:3]

        else:
            raise ValueError(f"Unknown by argument {by}. Choices: {COMPUTE_BY}")
    else:
        raise TypeError(f"by argument must be str")

    return by_standardized


def _standardize_hydrograph_segmentation_args(
    peak_quant: float, max_duration: int | float, by: str
) -> AnyTuple:
    peak_quant = _standardize_hydrograph_segmentation_peak_quant(peak_quant)

    max_duration = _standardize_hydrograph_segmentation_max_duration(max_duration)

    by = _standardize_hydrograph_segmentation_by(by)

    return (peak_quant, max_duration, by)
