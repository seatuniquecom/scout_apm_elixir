defmodule ScoutApm.Store do
  use GenServer
  import Logger

  alias ScoutApm.Internal.Layer
  alias ScoutApm.Internal.Metric

  # 60 seconds
  @tick_interval 60_000

  ## Client API

  def start_link do
    GenServer.start_link(__MODULE__, :ok, [name: __MODULE__])
  end

  def register_layer(layer) do
    case Process.whereis(__MODULE__) do
      nil -> Logger.info("Couldn't find worker!?")
      pid ->
        GenServer.cast(pid, {:register_layer, layer})
    end
  end

  def record_metric(%Metric{}=metric) do
    case Process.whereis(__MODULE__) do
      nil -> Logger.info("Couldn't find worker!?")
      pid ->
        GenServer.cast(pid, {:record_metric, metric})
    end
  end

  ## Server Callbacks

  def init(:ok) do
    start_timer()
    {:ok, initial_state()}
  end

  def handle_call({_}, _from, _state) do
    {:reply, nil}
  end

  # TODO: Scope should be on the layer
  def handle_cast({:register_layer, layer}, state) do
    time_elapsed = Layer.total_exclusive_time(layer)

    new_state = %{state |
      metric_set: ScoutApm.MetricSet.absorb(state.metric_set, layer.type, layer.name, time_elapsed, %{})
    }
    {:noreply, new_state}
  end

  def handle_cast({:record_metric, %Metric{}=metric}, state) do
    new_state = %{state |
      metric_set: ScoutApm.MetricSet.absorb(state.metric_set, metric.type, metric.name, metric.exclusive_time, metric.scope)
    }
    {:noreply, new_state}
  end

  def handle_info(:tick, state) do
    state[:metric_set]
    |> ScoutApm.Payload.new
    |> ScoutApm.Payload.encode
    |> log_payload()
    |> ScoutApm.Reporter.post

    {:noreply, initial_state()}
  end

  def initial_state do
    %{
      metric_set: ScoutApm.MetricSet.new()
    }
  end

  # Set up a timer that runs `handle_info(:tick, state)` on self every X milliseconds.
  def start_timer do
    :timer.send_interval(@tick_interval, :tick)
  end

  def log_payload(p) do
    Logger.info(inspect p)
    p
  end
end

