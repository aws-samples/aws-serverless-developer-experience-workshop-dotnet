using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Threading.Tasks;
using Amazon.EventBridge;
using Amazon.EventBridge.Model;

namespace Unicorn.Contracts.ContractService;

/// <summary>
/// Interface that defines the Publisher
/// </summary>
public interface IPublisher
{
    Task PublishEvent(Contract contract);
}

/// <summary>
/// Class that represents Publisher implementation.
/// </summary>
public class Publisher : IPublisher
{
    private readonly string? _eventBus;
    private readonly string? _serviceNamespace;
    private readonly AmazonEventBridgeClient _amazonEventBridgeClient;

    public Publisher()
    {
        _serviceNamespace = Environment.GetEnvironmentVariable("SERVICE_NAMESPACE");

        if (string.IsNullOrEmpty(_serviceNamespace))
        {
            throw new Exception("Environment variable SERVICE_NAMESPACE is not defined.");
        }

        _eventBus = Environment.GetEnvironmentVariable("EVENT_BUS");
        if (string.IsNullOrEmpty(_eventBus))
        {
            throw new Exception("Environment variable EVENT_BUS is not defined.");
        }

        _amazonEventBridgeClient = new AmazonEventBridgeClient();
    }
    
    public Publisher(string serviceNamespace, string eventBus)
    {
        _serviceNamespace = serviceNamespace;
        _eventBus = eventBus;
        _amazonEventBridgeClient = new AmazonEventBridgeClient();
    }

    public async Task PublishEvent(Contract contract)
    {
        var contractStatusChangedEvent = new ContractStatusChangedEvent(contract.PropertyId ?? "", contract.ContractId,
            contract.ContractStatus, contract.ContractLastModifiedOn);

        var detail = JsonSerializer.Serialize(contractStatusChangedEvent,
            new JsonSerializerOptions { IncludeFields = true });

        var request = new PutEventsRequest
        {
            Entries = new List<PutEventsRequestEntry>()
            {
                new()
                {
                    Detail = detail,
                    DetailType = "ContractStatusChanged",
                    EventBusName = _eventBus,
                    Source = _serviceNamespace,
                }
            }
        };

        await _amazonEventBridgeClient.PutEventsAsync(request);
    }
}