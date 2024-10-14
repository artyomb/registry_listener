
module ConfigDSL
  extend self
  def load(config_file)
    @path = [{}]
    class_eval File.read(config_file)
    @path.last
  end
  def collect(name, args, &block)
    (@path.last[name] ||= []) << args
    @path.push args
    yield if block_given?
    @path.pop
  end

  def OnPush(args, &) = collect(__method__, args, &)
  def OnTime(args, &block) = collect(__method__, args.merge( block:))
  def Push(args, &) = collect(__method__, args, &)
  def UpdateServices(endpoint, args = {}, &) = collect(__method__, args.merge(endpoint:), &)

end
