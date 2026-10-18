import base64
import unittest

from contract import MAX_PROMPT_CHARS, PayloadError, decode_payload


class ContractTests(unittest.TestCase):
    def test_prompt_only_is_valid_but_worker_requires_reference(self) -> None:
        payload = decode_payload({"prompt": "a stylized fantasy shield"})
        self.assertEqual(payload["prompt"], "a stylized fantasy shield")
        self.assertIsNone(payload["reference"])

    def test_reference_is_decoded_and_capped(self) -> None:
        raw = b"png-fixture"
        payload = decode_payload(
            {
                "prompt": "a stylized fantasy shield",
                "reference_image": {
                    "filename": "shield.png",
                    "mime_type": "image/png",
                    "data_base64": base64.b64encode(raw).decode(),
                },
            }
        )
        self.assertEqual(payload["reference"]["bytes"], raw)
        self.assertEqual(payload["reference"]["mime_type"], "image/png")

    def test_invalid_and_oversized_requests_are_rejected(self) -> None:
        with self.assertRaises(PayloadError):
            decode_payload({"prompt": ""})
        with self.assertRaises(PayloadError):
            decode_payload({"prompt": "x" * (MAX_PROMPT_CHARS + 1)})
        with self.assertRaises(PayloadError):
            decode_payload(
                {
                    "prompt": "x",
                    "reference_image": {
                        "mime_type": "image/gif",
                        "data_base64": base64.b64encode(b"x").decode(),
                    },
                }
            )


if __name__ == "__main__":
    unittest.main()
