pwd=`echo $PWD`.chomp
uid=`id -u`.chomp
gid=`id -g`.chomp

basecmd="docker run"
flags="--rm -ti"
curdir=%{-v #{pwd}:#{pwd} --workdir=#{pwd}}
userspec="-u #{uid}:#{gid}"

imagename=ARGV[0]
version="latest"


if "#{ENV["VERSION"]}".length != 0
  version=ENV["VERSION"]

elsif File.exist?(".#{imagename}.version")
  version="#{File.read(".#{imagename}.version").chomp}"
end
puts "# version: #{version}"

if "#{ENV["NETWORK"]}".length != 0
  network=ENV["NETWORK"]

elsif File.exist?(".#{imagename}.network")
  network="#{File.read(".#{imagename}.network").chomp}"
end

puts "# network: #{network}"

networkstring = ""
if network
  networkstring = "--network #{network}"
end



image = "#{imagename}:#{version}"

envvar_arr=[
  %{XDG_CACHE_HOME="#{pwd}/.cache/#{imagename}.#{version}"},
  %{XDG_DATA_HOME="#{pwd}/.data/#{imagename}.#{version}"},
  %{XDG_STATE_HOME="#{pwd}/.state/#{imagename}.#{version}"},
  %{XDG_RUNTIME_DIR_HOME="#{pwd}/.runtime/#{imagename}.#{version}"},
  %{PYTHONUSERBASE="#{pwd}/.pip/#{imagename}.#{version}"},
  %{BUNDLE_PATH="#{pwd}/.bundler"},
  'BUNDLE_DISABLE_SHARED_GEMS=true',
  "HOME=#{pwd}"
]

envvars = envvar_arr.map {|x| "-e #{x}" }.join(' ')

ports=[]

if "#{ENV["EXPOSE"]}".length != 0
  ports += ENV["EXPOSE"].split(",")

elsif File.exist?(".#{ARGV[0]}.ports")
  ports += File.read(".#{ARGV[0]}.ports").split("\n").to_a
end

use_gpu = false
gpu_runtime = "nvidia"
gpu_choice = "all"

if "#{ENV["GPU_RUNTIME"]}".length != 0
  gpu_runtime = ENV["GPU_RUNTIME"]
  use_gpu = true

elsif File.exist?(".#{ARGV[0]}.gpu_runtime")
  gpu_runtime = File.read(".#{ARGV[0]}.gpu_runtime")
  use_gpu = true
end

if "#{ENV["GPU"]}".length != 0
  gpu_choice = ENV["GPU"]
  use_gpu = true

elsif File.exist?(".#{ARGV[0]}.gpu_choice")
  gpu_choice = File.read(".#{ARGV[0]}.gpu_choice")
  use_gpu = true

end

gpustring = ""

if use_gpu
  puts "# using gpu runtime #{gpu_runtime}"
  puts "# using gpu #{gpu_choice}"
  gpustring = "--runtime=#{gpu_runtime} --gpus #{gpu_choice}"
end

portstring = ports.map{|x| "-p #{x}"}.join(',')

cmd2=ARGV[1]

ccmd=%{#{cmd2} #{ARGV[2..-1].join(' ')}}

arr = [
  basecmd,
  flags,
  curdir,
  userspec,
  envvars,
  portstring,
  gpustring,
  networkstring,
  image,
  ccmd
]

result = arr.join(' ')

print result
