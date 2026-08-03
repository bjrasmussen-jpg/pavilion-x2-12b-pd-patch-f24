# Reproducible test results

## Tested device

- HP Pavilion x2 Detachable, SKU `T1F46EA#ABD`
- Mainboard `8181`, revision `42.25`
- HP/AMI BIOS `F.24`, dated 2020-01-20
- ITE IT8987 EC; GigaDevice GD25B64B 8 MiB SPI flash
- Charger connected directly to C1: Anker label `A2697` (the current Anker
  product page calls the retail model `B2697`), with a 5 A e-marked cable and
  no other charger ports in use

## Charging result after the patch and a true EC power reset

Five consecutive Windows WMI samples reported:

| Field | Value |
| --- | ---: |
| PowerOnline | `True` |
| Charging | `True` |
| Discharging | `False` |
| Battery voltage | `8420 mV` |
| Net battery charge rate | `15952 mW` |
| Battery-side current (rate / voltage) | about `1.895 A` |
| Discharge rate | `0 mW` |
| Remaining capacity | `14349 mWh` |

`ChargeRate` is net power into the battery. It is not the USB-C PD contract
voltage, source current, or wall-input power; system consumption and conversion
losses are additional.

## Identity and EC state

| Field | Raw value | Interpretation |
| --- | --- | --- |
| EC identity slot `0x08B6-0x08B7` | `00 00` | empty slot |
| EC identity slot `0x08B8-0x08B9` | `FF FF` | unavailable/error sentinel; not an Anker VID |
| Firmware allowlist bytes | `03 F0` | USB-IF VID `0x03F0` (HP) |
| Firmware allowlist bytes | `04 B4` | USB-IF VID `0x04B4` (Cypress) |
| EC `0x0429` | `0A` | foreign-ID/mismatch latch is set while the gate state is also set |
| EC `0x1608` | `76` | GPH4 output bit is HIGH |
| EC `0x1D00` | `04` | gate-state mirror is HIGH |

Anker Innovations has USB-IF company VID `0x291A` (decimal 10522), but this is
not evidence that the A2697 advertises that value as a USB-PD Source Identity.
This platform exposes no Anker USB PnP device, cached Discover Identity payload,
or passive Source VID/PID. The actual Source VID/PID and the negotiated PDO/RDO
remain unmeasured.

The observed `0x07E0` transfer scratch buffer was:

```text
38 2D D8 00 01 00 02 01 03 01 00 14 00 00 00 00
```

It is a shared bus/transfer buffer, not a USB VID/PID.

## Charger capability (manufacturer specification)

With one port in use, Anker specifies C1/C2 as 9 V/3 A, 15 V/3 A, 20 V/5 A,
and 28 V/5 A, up to 140 W. C3 is specified up to 40 W. These are offered
capabilities, not the measured contract on this notebook.

Sources: [Anker specification](https://service.anker.com/fr/article-description/Specification-of-Anker-140W-Charger-A2697), [USB-IF VID list](https://www.usb.org/sites/default/files/vendor_ids07072026_0.pdf).
