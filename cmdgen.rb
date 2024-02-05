pwd=`echo $PWD`.chomp
uid=`id -u`.chomp
gid=`id -g`.chomp

basecmd="docker run"
flags="--rm -ti"
curdir=%{-v #{pwd}:#{pwd} --workdir=#{pwd}}
userspec="-u #{uid}:#{gid}"
envvar_arr=[
  %{BUNDLE_PATH="#{pwd}/.bundler"},
  'BUNDLE_DISABLE_SHARED_GEMS=true',
  "HOME=#{pwd}"
]

envvars = envvar_arr.map {|x| "-e #{x}" }.join(' ')

image=ARGV[0]

if File.exist?(".#{image}.version")
  image="#{ARGV[0]}:#{File.read(".#{image}.version").chomp}"
end

cmd2=ARGV[1]

ccmd=%{#{cmd2} #{ARGV[2..-1].join(' ')}}

arr = [
  basecmd,
  flags,
  curdir,
  userspec,
  envvars,
  image,
  ccmd
]

result = arr.join(' ')

print result
