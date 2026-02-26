require "base64"
require "openssl"
require "securerandom"

class User < ApplicationRecord
  PASSWORD_ITERATIONS = 210_000
  PASSWORD_DIGEST_BYTES = 32
  NAME_MAX_LENGTH = 60
  BIO_MAX_LENGTH = 500

  has_many :posts, dependent: :nullify
  has_many :comments, dependent: :destroy
  has_many :post_reactions, dependent: :destroy

  attr_accessor :password, :password_confirmation

  before_validation :normalize_email
  before_validation :normalize_profile_fields
  before_save :persist_password_digest, if: :password_present?

  validates :email, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 255 }
  validates :password, presence: true, confirmation: true, length: { minimum: 8 }, if: :password_required?
  validates :name, length: { maximum: NAME_MAX_LENGTH }
  validates :bio, length: { maximum: BIO_MAX_LENGTH }

  def authenticate(raw_password)
    return false unless password_digest.present?

    self.class.valid_password?(password_digest, raw_password.to_s) ? self : false
  end

  def display_name
    name.presence || email
  end

  def self.valid_password?(stored_digest, raw_password)
    algorithm, iterations, salt, expected_hash = stored_digest.to_s.split("$", 4)
    return false unless algorithm == "pbkdf2_sha256"
    return false if iterations.to_i <= 0 || salt.blank? || expected_hash.blank?

    computed_hash = Base64.strict_encode64(
      OpenSSL::PKCS5.pbkdf2_hmac(
        raw_password,
        salt,
        iterations.to_i,
        PASSWORD_DIGEST_BYTES,
        "sha256"
      )
    )

    ActiveSupport::SecurityUtils.secure_compare(expected_hash, computed_hash)
  rescue StandardError
    false
  end

  private

  def password_required?
    new_record? || password_present?
  end

  def password_present?
    password.present?
  end

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def normalize_profile_fields
    self.name = name.to_s.squish.presence
    self.bio = bio.to_s.strip.presence
  end

  def persist_password_digest
    salt = SecureRandom.hex(16)
    hash = OpenSSL::PKCS5.pbkdf2_hmac(
      password.to_s,
      salt,
      PASSWORD_ITERATIONS,
      PASSWORD_DIGEST_BYTES,
      "sha256"
    )

    self.password_digest = "pbkdf2_sha256$#{PASSWORD_ITERATIONS}$#{salt}$#{Base64.strict_encode64(hash)}"
  end
end
