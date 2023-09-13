// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.CloudWatchEvents;
using Amazon.Lambda.Core;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

// Assembly attribute to enable the Lambda function's JSON input to be converted into a .NET class.
// [assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Properties.PropertiesService;

public class ContractStatusChangedEventHandler
{
    private readonly IDynamoDBContext _dynamoDbContext;

    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    /// <exception cref="Exception">Init exception</exception>
    public ContractStatusChangedEventHandler()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();

        var dynamodbTable = Environment.GetEnvironmentVariable("CONTRACT_STATUS_TABLE");
        if (string.IsNullOrEmpty(dynamodbTable))
        {
            throw new Exception("Environment variable CONTRACT_STATUS_TABLE is not defined.");
        }

        AWSConfigsDynamoDB.Context.TypeMappings[typeof(ContractStatusChangedEvent)] =
            new TypeMapping(typeof(ContractStatusChangedEvent), dynamodbTable);

        var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
        _dynamoDbContext = new DynamoDBContext(new AmazonDynamoDBClient(), config);
    }


    /// <summary>
    /// Event handler for ContractStatusChangedEvent
    /// </summary>
    /// <param name="contractStatusChangedEvent">EventBridge event that triggers this function</param>
    /// <param name="context">Lambda Context runtime methods and attributes</param>
    public async Task FunctionHandler(CloudWatchEvent<ContractStatusChangedEvent> contractStatusChangedEvent,
        ILambdaContext context)
    {
        Console.WriteLine(JsonSerializer.Serialize(contractStatusChangedEvent));
        try
        {
            await SaveContractStatus(contractStatusChangedEvent.Detail).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            Console.WriteLine(e.Message);
            throw new ContractStatusChangedEventHandlerException(e.Message);
        }
    }

    private async Task SaveContractStatus(ContractStatusChangedEvent contractStatus)
    {
        Console.WriteLine($"Updating contract status for Property ID: {contractStatus.PropertyId}");
        await _dynamoDbContext.SaveAsync(contractStatus).ConfigureAwait(false);
        Console.WriteLine($"Contract status updated for Property ID: {contractStatus.PropertyId}");
    }
}