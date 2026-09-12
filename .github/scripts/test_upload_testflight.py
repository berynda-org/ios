import contextlib
import io
import subprocess
import unittest
from unittest.mock import patch

from upload_testflight import validate_and_upload


class UploadResultTests(unittest.TestCase):
    def run_outputs(self, outputs):
        results = [subprocess.CompletedProcess([], code, text) for code, text in outputs]
        with patch("upload_testflight.subprocess.run", side_effect=results) as run:
            with contextlib.redirect_stdout(io.StringIO()):
                validate_and_upload("Berynda.ipa", "test-key-id", "test-issuer-id")
            return run

    def test_modern_success_uploads_only_after_validation(self):
        run = self.run_outputs([(0, "VERIFY SUCCEEDED with no errors"), (0, "UPLOAD SUCCEEDED with no errors")])
        self.assertIn("--validate-app", run.call_args_list[0].args[0])
        self.assertIn("--upload-app", run.call_args_list[1].args[0])

    def test_legacy_success_messages_are_accepted(self):
        self.run_outputs([(0, "No errors validating archive"), (0, "No errors uploading archive")])

    def test_zero_exit_validation_rejection_never_uploads(self):
        rejection = "2026-09-12 ERROR: [altool] Validation failed (409) Invalid bundle.\nVERIFY FAILED with 1 error\nFailed to validate package."
        with patch("upload_testflight.subprocess.run", return_value=subprocess.CompletedProcess([], 0, rejection)) as run:
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(RuntimeError):
                validate_and_upload("Berynda.ipa", "test-key-id", "test-issuer-id")
            self.assertEqual(run.call_count, 1)

    def test_zero_exit_upload_rejection_fails(self):
        with self.assertRaises(RuntimeError):
            self.run_outputs([(0, "VERIFY SUCCEEDED"), (0, "UPLOAD FAILED with 1 error")])

    def test_nonzero_exit_fails_even_with_success_text(self):
        with self.assertRaises(RuntimeError):
            self.run_outputs([(1, "VERIFY SUCCEEDED")])

    def test_missing_success_confirmation_fails_closed(self):
        with self.assertRaises(RuntimeError):
            self.run_outputs([(0, "Running altool...")])


if __name__ == "__main__":
    unittest.main()
