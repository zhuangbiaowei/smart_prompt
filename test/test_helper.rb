require 'net/http'

# Stub helpers for tests that need to fake out Net::HTTP without touching the network.
#
# The active environment ships minitest 6.0, which removed minitest/mock (and thus
# Object#stub). We stub Net::HTTP manually instead: the original method objects are
# captured once at load time, and each helper restores directly from them via
# define_singleton_method(name, original) — so repeated stubbing never accumulates
# wrapper layers.
module NetHTTPStub
  ORIGINAL_NEW = Net::HTTP.method(:new)
  ORIGINAL_GET_RESPONSE = Net::HTTP.method(:get_response)

  # Yield a block in which Net::HTTP.new returns +fake+ (ignoring host/port args).
  def with_http_new(fake)
    Net::HTTP.define_singleton_method(:new) { |*_| fake }
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, ORIGINAL_NEW)
  end

  # Yield a block in which Net::HTTP.get_response returns +fake+ (ignoring the uri).
  def with_http_get_response(fake)
    Net::HTTP.define_singleton_method(:get_response) { |*_| fake }
    yield
  ensure
    Net::HTTP.define_singleton_method(:get_response, ORIGINAL_GET_RESPONSE)
  end
end

# Temporarily replace an instance method on +obj+ with a fixed return value (or a
# callable) for the duration of the block, then restore the original. minitest 6 has
# no Object#stub, so this is the manual equivalent.
def with_stub_method(obj, name, value)
  original = obj.method(name)
  if value.respond_to?(:call)
    obj.define_singleton_method(name) { |*args| value.call(*args) }
  else
    obj.define_singleton_method(name) { |*_| value }
  end
  yield
ensure
  obj.define_singleton_method(name, original)
end
