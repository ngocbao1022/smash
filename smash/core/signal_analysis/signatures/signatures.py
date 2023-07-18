from __future__ import annotations

from smash._constant import PEAK_QUANT, MAX_DURATION

from smash.fcore._mwd_signatures import signature_computation

from smash.core.signal_analysis.signatures._standardize import (
    _standardize_compute_signatures_args,
)

from smash.core.signal_analysis.segmentation._tools import _events_grad, _get_season

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from smash.core.model.model import Model

import numpy as np
import pandas as pd
import warnings


__all__ = ["Signatures", "compute_signatures"]


class Signatures(dict):
    """
    Represents signatures computation result.

    Notes
    -----
    This class is essentially a subclass of dict with attribute accessors.

    Attributes
    ----------
    cont : dict
        A dataframe representing observed or simulated continuous signatures.
        The column names consist of the catchment code and studied signature names.

    event : dict
        A dataframe representing observed or simulated flood event signatures.
        The column names consist of the catchment code, the season that event occurrs, the beginning/end of each event and studied signature names.

    See Also
    --------
    Model.signatures: Compute continuous or/and flood event signatures of the Model.

    """

    def __getattr__(self, name):
        try:
            return self[name]
        except KeyError as e:
            raise AttributeError(name) from e

    __setattr__ = dict.__setitem__
    __delattr__ = dict.__delitem__

    def __repr__(self):
        if self.keys():
            m = max(map(len, list(self.keys()))) + 1
            return "\n".join(
                [
                    k.rjust(m) + ": " + repr(v)
                    for k, v in sorted(self.items())
                    if not k.startswith("_")
                ]
            )
        else:
            return self.__class__.__name__ + "()"

    def __dir__(self):
        return list(self.keys())


def compute_signatures(
    model: Model,
    sign: str | list | None = None,
    event_seg: dict | None = None,
    by: str = "sim",
):
    """
    Compute continuous or/and flood event signatures of the Model.

    .. hint::
        See the :ref:`User Guide <user_guide.in_depth.signatures.computation>` and :ref:`Math / Num Documentation <math_num_documentation.signal_analysis.hydrological_signatures>` for more.

    Parameters
    ----------
    model : Model
        Model object.

    sign : str, list of str or None, default None
        Define signature(s) to compute. Should be one of

        - 'Crc', 'Crchf', 'Crclf', 'Crch2r', 'Cfp2', 'Cfp10', 'Cfp50', 'Cfp90' (continuous signatures)
        - 'Eff', 'Ebf', 'Erc', 'Erchf', 'Erclf', 'Erch2r', 'Elt', 'Epf' (flood event signatures)

        .. note::
            If not given, all of continuous and flood event signatures will be computed.

    event_seg : dict or None, default None
        A dictionary of event segmentation options when calculating flood event signatures. The keys are

        - 'peak_quant'
        - 'max_duration'

        See `smash.Model.event_segmentation` for more.

        .. note::
            If not given in case flood signatures are computed, the default values will be set for these parameters.

    by: str, default 'obs'
        Compute signatures based on observed discharges (obs) or simulated discharges (sim).

    Returns
    -------
    res : Signatures
        The signatures computation results represented as a `Signatures` object.

    See Also
    --------
    Signatures: Represents signatures computation result.

    Examples
    --------
    >>> setup, mesh = smash.load_dataset("cance")
    >>> model = smash.Model(setup, mesh)
    >>> model.run(inplace=True)

    Compute all observed and simulated signatures:

    >>> res = model.signatures()
    >>> res.cont["obs"]  # observed continuous signatures
            code       Crc     Crchf  ...   Cfp50      Cfp90
    0  V3524010  0.516207  0.191349  ...  3.3225  42.631802
    1  V3515010  0.509180  0.147217  ...  1.5755  10.628400
    2  V3517010  0.514302  0.148364  ...  0.3235   2.776700

    [3 rows x 9 columns]

    >>> res.event["sim"]  # simulated flood event signatures
            code  season               start  ...  Elt         Epf
    0  V3524010  autumn 2014-11-03 03:00:00  ...    3  106.190651
    1  V3515010  autumn 2014-11-03 10:00:00  ...    0   21.160324
    2  V3517010  autumn 2014-11-03 08:00:00  ...    1   5.613392

    [3 rows x 12 columns]

    """

    cs, es, event_seg, by = _standardize_compute_signatures_args(sign, event_seg, by)

    res = _compute_signatures(model, cs, es, by, **event_seg)

    return Signatures(res)


# TODO: Add function check_unknown_options
def _compute_signatures(
    instance: Model,
    cs: list[str],
    es: list[str],
    by: str,
    peak_quant: float = PEAK_QUANT,
    max_duration: float = MAX_DURATION,
    **unknown_options,
):
    prcp_cvt = (
        instance.atmos_data.mean_prcp
        * 0.001
        * instance.mesh.area_dln[..., np.newaxis]
        / instance.setup.dt
    )  # convert precip from mm to m3/s

    date_range = pd.date_range(
        start=instance.setup.start_time,
        periods=prcp_cvt.shape[1],
        freq=f"{int(instance.setup.dt)}s",
    )

    col_cs = ["code"] + cs
    col_es = ["code", "season", "start", "end"] + es

    df_cs = pd.DataFrame(columns=col_cs)
    df_es = pd.DataFrame(columns=col_es)

    if len(cs) + len(es) > 0:
        for i, catchment in enumerate(instance.mesh.code):
            prcp = prcp_cvt[
                i, :
            ]  # already conversion of instance.atmos_data.mean_prcp[i, :]

            if by == "obs":
                q = instance.obs_response.q[i, :].copy()

            else:
                q = instance.sim_response.q[i, :].copy()

            if (prcp < 0).all() or (q < 0).all():
                warnings.warn(
                    f"Catchment {catchment} has no precipitation or/and discharge data"
                )

                row_cs = pd.DataFrame(
                    [[catchment] + [np.nan] * (len(col_cs) - 1)], columns=col_cs
                )
                row_es = pd.DataFrame(
                    [[catchment] + [np.nan] * (len(col_es) - 1)], columns=col_es
                )

                df_cs = pd.concat([df_cs, row_cs], ignore_index=True)
                df_es = pd.concat([df_es, row_es], ignore_index=True)

            else:
                if len(cs) > 0:
                    csignatures = [
                        signature_computation(prcp, q, signature) for signature in cs
                    ]

                    row_cs = pd.DataFrame([[catchment] + csignatures], columns=col_cs)

                    df_cs = pd.concat([df_cs, row_cs], ignore_index=True)

                if len(es) > 0:
                    list_events = _events_grad(
                        prcp, q, peak_quant, max_duration, instance.setup.dt
                    )

                    if len(list_events) == 0:
                        row_es = pd.DataFrame(
                            [[catchment] + [np.nan] * (len(col_es) - 1)],
                            columns=col_es,
                        )

                        df_es = pd.concat([df_es, row_es], ignore_index=True)

                    else:
                        for t in list_events:
                            ts = t["start"]
                            te = t["end"]

                            event_prcp = prcp[ts : te + 1]
                            event_q = q[ts : te + 1]

                            season = _get_season(date_range[ts].date())

                            esignatures = [
                                signature_computation(event_prcp, event_q, signature)
                                for signature in es
                            ]

                            row_es = pd.DataFrame(
                                [
                                    [
                                        catchment,
                                        season,
                                        date_range[ts],
                                        date_range[te],
                                    ]
                                    + esignatures
                                ],
                                columns=col_es,
                            )

                            df_es = pd.concat([df_es, row_es], ignore_index=True)

    return dict(
        zip(
            ["cont", "event"],
            [
                df_cs,
                df_es,
            ],
        )
    )
