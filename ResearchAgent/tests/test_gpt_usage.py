import unittest
from gpt_usage import display_snapshot


class UsageTests(unittest.TestCase):
    def test_week_in_secondary_and_expired_credits(self):
        result = {'rateLimitsByLimitId': {'codex': {
            'primary': {'windowDurationMins': 300, 'usedPercent': 5},
            'secondary': {'windowDurationMins': 10080, 'usedPercent': 67, 'resetsAt': 200},
        }}, 'rateLimitResetCredits': {'availableCount': 2, 'credits': [
            {'id': 'expired', 'status': 'available', 'expiresAt': 99},
            {'id': 'later', 'status': 'available', 'expiresAt': 200},
            {'id': 'earlier', 'status': 'available', 'expiresAt': 150},
            {'id': 'used', 'status': 'redeemed', 'expiresAt': 300},
        ]}}
        snapshot = display_snapshot(result, now=100)
        self.assertEqual(snapshot['usedPercent'], 67)
        self.assertEqual(snapshot['weeklyResetsAt'], 200)
        self.assertEqual([r['id'] for r in snapshot['resets']], ['earlier', 'later'])

    def test_unknown_is_not_zero(self):
        snapshot = display_snapshot({'rateLimitResetCredits': {'availableCount': 3, 'credits': None}})
        self.assertIsNone(snapshot['usedPercent'])
        self.assertFalse(snapshot['detailsAvailable'])
        self.assertEqual(snapshot['availableCount'], 3)

    def test_legacy_primary_and_no_private_fields(self):
        snapshot = display_snapshot({'accountId': 'private', 'rateLimits': {
            'primary': {'windowDurationMins': 10080, 'usedPercent': 120, 'resetsAt': 200}}})
        self.assertEqual(snapshot['usedPercent'], 100)
        self.assertNotIn('accountId', snapshot)


if __name__ == '__main__':
    unittest.main()
