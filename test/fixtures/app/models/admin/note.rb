class Admin::Note < ApplicationRecord
  belongs_to :audit_log             # resolves to Admin::AuditLog
  belongs_to :ghost                 # unknown model -> warning
end
