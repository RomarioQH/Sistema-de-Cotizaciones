import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lambda_src'))
import common


class MappingTests(unittest.TestCase):
    def test_roles_sql_to_ui(self):
        self.assertEqual(common.to_role('ADMIN'), 'admin')
        self.assertEqual(common.to_role('SELLER'), 'vendedor')
        self.assertEqual(common.to_role('CUSTOMER'), 'cliente')

    def test_roles_ui_to_sql(self):
        self.assertEqual(common.from_role('admin'), 'ADMIN')
        self.assertEqual(common.from_role('vendedor'), 'SELLER')
        self.assertEqual(common.from_role('cliente'), 'CUSTOMER')

    def test_status_mapping_round_trip(self):
        pairs = [('DRAFT', 'Borrador'), ('PENDING', 'Enviada'), ('APPROVED', 'Aceptada'), ('OBSERVED', 'Rechazada')]
        for sql, ui in pairs:
            self.assertEqual(common.to_quote_status(sql), ui)
            self.assertEqual(common.from_quote_status(ui), sql)

    def test_user_mapping(self):
        user = common.map_user({'userId': 7, 'name': 'Ada Lovelace', 'email': 'ada@example.com',
                                'roleCode': 'SELLER', 'statusCode': 'ACTIVE'})
        self.assertEqual(user['id'], '7')
        self.assertEqual(user['role'], 'vendedor')
        self.assertEqual(user['status'], 'Activo')
        self.assertEqual(user['initials'], 'AL')


if __name__ == '__main__':
    unittest.main()
