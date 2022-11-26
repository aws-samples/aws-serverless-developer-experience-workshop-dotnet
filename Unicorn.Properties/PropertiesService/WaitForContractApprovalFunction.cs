// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.Core;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

// Assembly attribute already set
// [assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace Unicorn.Properties.PropertiesService;

/// <summary>
/// Represents the AWS Lambda function responsible for pausing the properties approval workflow until the Contract
/// has been approved
/// </summary>
public class WaitForContractApprovalFunction
{
    private readonly IDynamoDBContext _dynamoDbContext;

    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    /// <exception cref="Exception">Init exception</exception>
    public WaitForContractApprovalFunction()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();

        var dynamodbTable = Environment.GetEnvironmentVariable("CONTRACT_STATUS_TABLE");
        if (string.IsNullOrEmpty(dynamodbTable))
        {
            throw new Exception("Environment variable CONTRACT_STATUS_TABLE is not defined.");
        }

        AWSConfigsDynamoDB.Context.TypeMappings[typeof(ContractStatusItem)] =
            new TypeMapping(typeof(ContractStatusItem), dynamodbTable);

        var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
        _dynamoDbContext = new DynamoDBContext(new AmazonDynamoDBClient(), config);
    }


    /// <summary>
    /// Event handler for ContractStatusChangedEvent
    /// </summary>
    /// <param name="input">The input payload</param>
    /// <param name="context">Lambda Context runtime methods and attributes</param>
    [Logging(LogEvent = true)]
    [Metrics(CaptureColdStart = true)]
    [Tracing]
    public async Task FunctionHandler(object input, ILambdaContext context)
    {
        var document = JsonSerializer.SerializeToDocument(input);
        var propertyId = document.RootElement.GetProperty("Input").GetProperty("PropertyId").GetString() ?? "";
        var taskToken = document.RootElement.GetProperty("TaskToken").GetString();
       
        Logger.LogInformation($"Property Id : {propertyId}");
        Logger.LogInformation($"Task Token : {taskToken}");

        var contractStatus = await GetContractStatus(propertyId).ConfigureAwait(false);
        if (contractStatus == null)
        {
            throw new ContractStatusNotFoundException($"Could not find property with ID: {propertyId}");
        }
        contractStatus.SfnWaitApprovedTaskToken = taskToken;
        await SaveContractStatus(contractStatus).ConfigureAwait(false);
    }
    
    /// <summary>
    /// Retrieves the contract status for a specifies property
    /// </summary>
    /// <param name="propertyId">Property ID</param>
    /// <returns>Instance of <see cref="ContractStatusItem"/></returns>
    [Tracing(SegmentName = "Get Contract Status")]
    private async Task<ContractStatusItem?> GetContractStatus(string propertyId)
    {
        ContractStatusItem? item;
        try
        {
            Logger.LogInformation($"Getting Contract Status for {propertyId}");
            item = await _dynamoDbContext.LoadAsync<ContractStatusItem>(propertyId).ConfigureAwait(false);
        }
        catch (Exception e)
        {
            Logger.LogInformation($"Error loading contract {propertyId}: {e.Message}");
            item = null;
        }
        Logger.LogInformation($"Found contact: {item != null}");
        return item;
    }

    [Tracing(SegmentName = "Save Contract Status")]
    private async Task SaveContractStatus(ContractStatusItem contractStatus)
    {
        try
        {
            Logger.LogInformation($"Saving contract for Property ID: {contractStatus.PropertyId}");
            await _dynamoDbContext.SaveAsync(contractStatus);
        }
        catch (Exception e)
        {
            Logger.LogError(e.Message);
            throw;
        }
    }
}