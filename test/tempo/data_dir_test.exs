defmodule Tempo.Holidays.DataDirTest do
  # Sets the application's `:data_dir`, which every reader of the data sees.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Tempo.Holidays.Update
  alias Tempo.Holidays.{Build, Data}

  doctest Build

  setup do
    on_exit(fn -> Application.delete_env(:tempo_holidays, :data_dir) end)
  end

  describe "building the data" do
    @tag :tmp_dir
    test "an invalid version or a directory it cannot make is an error, not a raise",
         %{tmp_dir: tmp_dir} do
      assert Build.build(version: "latest", directory: tmp_dir) ==
               {:error, {:invalid_version, "latest"}}

      not_a_directory = Path.join(tmp_dir, "file")
      File.write!(not_a_directory, "")

      assert {:error, {:directory, _directory, :enotdir}} =
               Build.build(directory: Path.join(not_a_directory, "holidays"))

      assert Build.message({:directory, "/x", :enotdir}) == "could not make /x: not a directory"
    end
  end

  # A data directory with one territory of the package's own data and a
  # `VERSION` marker of the given release and format.
  defp data_dir(tmp_dir, marker) do
    source = Path.join(Application.app_dir(:tempo_holidays, "priv/holidays"), "AU.etf")
    File.cp!(source, Path.join(tmp_dir, "AU.etf"))
    File.write!(Path.join(tmp_dir, "VERSION"), marker)
    tmp_dir
  end

  describe "the data the library reads" do
    @tag :tmp_dir
    test "is the configured directory's, where its format is this release's", %{tmp_dir: tmp_dir} do
      Application.put_env(:tempo_holidays, :data_dir, data_dir(tmp_dir, Data.marker("9.9.9")))

      assert Data.version() == {:ok, "9.9.9"}
      assert Data.territories() == ["AU"]
    end

    @tag :tmp_dir
    test "is the package's own where the configured data is another format", %{tmp_dir: tmp_dir} do
      Application.put_env(:tempo_holidays, :data_dir, data_dir(tmp_dir, "9.9.9+1"))

      assert Data.version() == {:ok, Build.pinned_version()}
      assert "US" in Data.territories()
    end

    test "is the package's own where none is configured, or it cannot be found" do
      assert Data.version() == {:ok, Build.pinned_version()}

      Application.put_env(:tempo_holidays, :data_dir, {:no_such_application, "holidays"})
      assert Data.version() == {:ok, Build.pinned_version()}
    end
  end

  describe "the directory mix tempo.holidays.update writes" do
    test "is the package's own in tempo_holidays itself" do
      assert Update.target_directory(:tempo_holidays) == Build.default_directory()
    end

    test "is priv/<path> of the application that names itself in :data_dir" do
      Application.put_env(:tempo_holidays, :data_dir, {:my_app, "holidays"})
      root = Path.dirname(Mix.Project.project_file())

      assert Update.target_directory(:my_app) == Path.join([root, "priv", "holidays"])
    end

    test "is an absolute path given as :data_dir" do
      Application.put_env(:tempo_holidays, :data_dir, "/var/lib/holidays")
      assert Update.target_directory(:my_app) == "/var/lib/holidays"
    end

    test "is an error, saying what to configure, where none is configured or another application is named" do
      assert_raise Mix.Error, ~r/config :tempo_holidays, data_dir: \{:my_app, "holidays"\}/, fn ->
        Update.target_directory(:my_app)
      end

      Application.put_env(:tempo_holidays, :data_dir, {:other_app, "holidays"})
      assert_raise Mix.Error, ~r/:other_app/, fn -> Update.target_directory(:my_app) end
    end
  end

  test "a version is three numbers, an error before anything is downloaded" do
    assert Build.build(version: "latest") == {:error, {:invalid_version, "latest"}}
    assert Build.message({:invalid_version, "latest"}) =~ "three numbers"
  end
end
