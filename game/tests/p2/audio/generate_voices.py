"""Regenerate the two field speech banks with eSpeak NG. Run only during asset authoring."""
import argparse
import base64
import ctypes as C
import hashlib
import json
from pathlib import Path

AUDIO = Path(__file__).resolve().parents[3] / "presentation/audio"
CALLBACK = C.CFUNCTYPE(C.c_int, C.POINTER(C.c_short), C.c_int, C.c_void_p)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path, help="eSpeak NG DLL alongside espeak-ng-data")
    args = parser.parse_args()
    lib = C.CDLL(str(args.library.resolve()))
    lib.espeak_Info.restype = C.c_char_p
    lib.espeak_Synth.argtypes = [C.c_char_p, C.c_size_t, C.c_uint, C.c_int, C.c_uint, C.c_uint,
                                 C.c_void_p, C.c_void_p]
    chunks = []

    @CALLBACK
    def collect(samples, count, _events):
        if samples and count:
            chunks.append(C.string_at(samples, 2 * count))
        return 0

    rate = lib.espeak_Initialize(2, 0, str(args.library.resolve().parent).encode(), 0)
    if rate <= 0:
        raise RuntimeError("eSpeak NG initialization failed")
    lib.espeak_SetSynthCallback(collect)
    print("eSpeak NG", lib.espeak_Info(None).decode(), rate, "Hz")
    captions = (AUDIO / "captions.tres").read_text("utf-8")
    for locale, voice in (("zh", b"cmn"), ("en", b"en-us")):
        entries, _ = json.JSONDecoder().raw_decode(captions.split(f"metadata/{locale} = ", 1)[1])
        if lib.espeak_SetVoiceByName(voice) != 0:
            raise RuntimeError(f"missing {voice!r} voice")
        lines = ['[gd_resource type="Resource" format=3]']
        resources = []
        for key, phrase in entries.items():
            if not (key.startswith("audio.order.") or key == "audio.warning"):
                continue
            encoded = phrase.encode("utf-8")
            chunks.clear()
            lib.espeak_ng_SetRandSeed(241124)
            if lib.espeak_Synth(encoded, len(encoded) + 1, 0, 1, 0, 1, None, None) != 0:
                raise RuntimeError(f"synthesis failed for {key}")
            samples = b"".join(chunks)
            if len(samples) < rate // 2:
                raise ValueError(f"empty or incomplete clip for {key}")
            pcm = base64.b64encode(samples).decode("ascii")
            cue = key.rsplit(".", 1)[1]
            lines.extend(("", f'[sub_resource type="AudioStreamWAV" id="{cue}"]',
                          "format = 1", f"mix_rate = {rate}", f'data = PackedByteArray("{pcm}")'))
            resources.append(f'"{key}": SubResource("{cue}")')
        lines.extend(("", "[resource]", "metadata/clips = {", ",\n".join(resources), "}", ""))
        path = AUDIO / f"orders_{locale}.tres"
        data = "\n".join(lines).encode()
        path.write_bytes(data)
        print(path.name, len(resources), hashlib.sha256(data).hexdigest())
    lib.espeak_Terminate()


if __name__ == "__main__":
    main()
