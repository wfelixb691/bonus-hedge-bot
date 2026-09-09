"""
Lot Calculator Module for Dual-MT5 Hedging Bot.
Handles lot sizing calculations, bonus equity ratios, and broker step normalization.
"""

from typing import Optional
import math


class LotCalculator:
    def __init__(
        self,
        mode: str = "multiplier",
        multiplier: float = 1.1,
        min_lot: float = 0.01,
        max_lot: float = 50.0,
        lot_step: float = 0.01,
    ):
        self.mode = mode.lower()
        self.multiplier = float(multiplier)
        self.min_lot = float(min_lot)
        self.max_lot = float(max_lot)
        self.lot_step = float(lot_step)

    def normalize_lot(
        self,
        raw_lot: float,
        volume_min: Optional[float] = None,
        volume_max: Optional[float] = None,
        volume_step: Optional[float] = None,
    ) -> float:
        """
        Normalizes lot size according to broker volume limits and steps.
        """
        step = volume_step if volume_step and volume_step > 0 else self.lot_step
        v_min = volume_min if volume_min and volume_min > 0 else self.min_lot
        v_max = volume_max if volume_max and volume_max > 0 else self.max_lot

        # Calculate decimal places from step (e.g. 0.01 -> 2 decimals)
        if step > 0:
            decimals = max(0, int(round(-math.log10(step))))
            # Round to nearest valid step
            steps_count = round(raw_lot / step)
            calculated_lot = round(steps_count * step, decimals)
        else:
            calculated_lot = round(raw_lot, 2)

        # Clamp between min and max
        final_lot = max(v_min, min(v_max, calculated_lot))
        return round(final_lot, 2)

    def calculate_slave_lot(
        self,
        master_lot: float,
        equity_a: Optional[float] = None,
        equity_b: Optional[float] = None,
        volume_min: Optional[float] = None,
        volume_max: Optional[float] = None,
        volume_step: Optional[float] = None,
    ) -> float:
        """
        Calculates the target lot size on Slave (Account B) based on Master lot and configured mode.
        """
        if master_lot <= 0:
            return 0.0

        if self.mode == "equity_ratio" and equity_a and equity_b and equity_a > 0:
            ratio = equity_b / equity_a
            raw_lot = master_lot * ratio
        else:
            # Default to multiplier mode
            raw_lot = master_lot * self.multiplier

        return self.normalize_lot(
            raw_lot=raw_lot,
            volume_min=volume_min,
            volume_max=volume_max,
            volume_step=volume_step,
        )
