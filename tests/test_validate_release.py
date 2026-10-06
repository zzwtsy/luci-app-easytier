import unittest

from scripts.validate_release import ReleaseValidationError, validate_release


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.responses = {}
        self.requests = []

    def status_request(self, url, token):
        self.requests.append((url, token))
        response = self.responses.get(url, 404)
        if isinstance(response, Exception):
            raise response
        return response

    def validate(self, *, tag="v3.0.0", ref="refs/heads/main", default_branch="main"):
        return validate_release(
            tag=tag,
            git_ref=ref,
            default_branch=default_branch,
            repository="owner/repo",
            api_url="https://api.github.test",
            token="test-token",
            status_request=self.status_request,
        )

    def test_build_without_tag_is_allowed_on_non_default_branch(self):
        self.validate(tag="", ref="refs/heads/feature", default_branch="main")
        self.assertEqual(self.requests, [])

    def test_release_from_default_branch_with_no_existing_names_is_allowed(self):
        self.validate()
        self.assertEqual(len(self.requests), 2)
        self.assertTrue(all(token == "test-token" for _, token in self.requests))

    def test_repository_default_branch_is_not_hard_coded(self):
        self.validate(ref="refs/heads/trunk", default_branch="trunk")
        self.assertEqual(len(self.requests), 2)

    def test_release_from_non_default_branch_is_rejected_before_api_calls(self):
        with self.assertRaisesRegex(ReleaseValidationError, "default branch"):
            self.validate(ref="refs/heads/feature")
        self.assertEqual(self.requests, [])

    def test_existing_git_tag_is_rejected(self):
        self.responses[
            "https://api.github.test/repos/owner/repo/git/ref/tags/v3.0.0"
        ] = 200
        with self.assertRaisesRegex(ReleaseValidationError, "Git tag .* already exists"):
            self.validate()

    def test_existing_release_without_git_tag_is_rejected(self):
        self.responses[
            "https://api.github.test/repos/owner/repo/releases/tags/v3.0.0"
        ] = 200
        with self.assertRaisesRegex(
            ReleaseValidationError, "GitHub Release .* already exists"
        ):
            self.validate()

    def test_api_errors_fail_closed(self):
        for response in (403, 500, OSError("connection reset")):
            with self.subTest(response=response):
                self.responses = {
                    "https://api.github.test/repos/owner/repo/git/ref/tags/v3.0.0": response
                }
                with self.assertRaises(ReleaseValidationError):
                    self.validate()

    def test_unsupported_tag_characters_are_rejected(self):
        with self.assertRaisesRegex(ReleaseValidationError, "unsupported characters"):
            self.validate(tag="release/3.0.0")
        self.assertEqual(self.requests, [])


if __name__ == "__main__":
    unittest.main()
