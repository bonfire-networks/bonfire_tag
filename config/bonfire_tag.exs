use Mix.Config

config :bonfire_tag,
  otp_app: :your_app_name,
  web_module: Bonfire.Web,
  repo_module: Bonfire.Repo,
  templates_path: "lib"
