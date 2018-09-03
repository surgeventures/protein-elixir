defmodule Protein.UtilsTest do
  use ExUnit.Case, async: true
  alias Protein.Utils

  describe "get_config/3" do
    test "gets value" do
      opts = [foo: "bar"]
      assert Utils.get_config(opts, :foo, 0) == "bar"
    end

    test "gets default value" do
      opts = [foo: "bar"]
      assert Utils.get_config(opts, :aaa, 0) == 0
    end

    test "gets system value" do
      System.put_env("SYSTEM_ENV_NAME", "system_env_value")
      opts = [foo: {:system , "SYSTEM_ENV_NAME"}]
      assert Utils.get_config(opts, :foo, 0) == "system_env_value"
    end
  end

  describe "resolve_adapter_server_mod/1" do
    test "correct string" do
      assert :"test.Server" == Utils.resolve_adapter_server_mod("test")
    end
  end
end
