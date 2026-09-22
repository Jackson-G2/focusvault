import unittest

from scripts.vaulty_supporter_monitor import summarize, utc_day_bounds


class SupporterMonitorTests(unittest.TestCase):
    def test_summarizes_only_paid_vaulty_aud_orders_and_refunds(self):
        sessions = [
            {
                "id": "cs_paid_1",
                "created": 100,
                "status": "complete",
                "payment_status": "paid",
                "currency": "aud",
                "amount_total": 2900,
                "payment_intent": "pi_1",
                "metadata": {"product": "vaulty-supporter"},
            },
            {
                "id": "cs_unpaid",
                "created": 101,
                "status": "complete",
                "payment_status": "unpaid",
                "currency": "aud",
                "amount_total": 2900,
                "metadata": {"product": "vaulty-supporter"},
            },
            {
                "id": "cs_other_product",
                "created": 102,
                "status": "complete",
                "payment_status": "paid",
                "currency": "aud",
                "amount_total": 9900,
                "payment_intent": "pi_other",
                "metadata": {"product": "other-product"},
            },
            {
                "id": "cs_paid_1",
                "created": 100,
                "status": "complete",
                "payment_status": "paid",
                "currency": "aud",
                "amount_total": 2900,
                "payment_intent": "pi_1",
                "metadata": {"product": "vaulty-supporter"},
            },
        ]
        refunds = [
            {"id": "re_1", "created": 110, "status": "succeeded", "amount": 500, "payment_intent": "pi_1"},
            {"id": "re_other", "created": 111, "status": "succeeded", "amount": 9900, "payment_intent": "pi_other"},
        ]

        report = summarize(sessions, refunds)

        self.assertEqual(report["order_count"], 1)
        self.assertEqual(report["gross_aud"], "29.00")
        self.assertEqual(report["refund_count"], 1)
        self.assertEqual(report["refunded_aud"], "5.00")
        self.assertEqual(report["net_aud"], "24.00")
        self.assertEqual(report["orders"][0]["checkout_session_id"], "cs_paid_1")
        self.assertEqual(report["refunds"][0]["refund_id"], "re_1")
        self.assertEqual(report["status"], "read-only")

    def test_price_id_can_identify_a_paid_order_without_metadata(self):
        sessions = [
            {
                "id": "cs_price_match",
                "created": 100,
                "status": "complete",
                "payment_status": "paid",
                "currency": "aud",
                "amount_total": 2900,
                "payment_intent": "pi_price",
                "line_items": {"data": [{"price": {"id": "price_vaulty"}}]},
            }
        ]
        report = summarize(sessions, [], price_id="price_vaulty")
        self.assertEqual(report["order_count"], 1)
        self.assertEqual(report["gross_aud"], "29.00")

    def test_utc_day_bounds_are_inclusive_by_calendar_end(self):
        start_ts, end_ts, start, end = utc_day_bounds("2026-09-06", "2026-09-19")
        self.assertEqual((start, end), ("2026-09-06", "2026-09-19"))
        self.assertEqual(end_ts - start_ts, 14 * 24 * 60 * 60)


if __name__ == "__main__":
    unittest.main()
