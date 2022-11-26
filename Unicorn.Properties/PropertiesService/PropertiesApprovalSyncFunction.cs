// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using System.Text.Json;
using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.Core;
using Amazon.Lambda.DynamoDBEvents;
using Amazon.StepFunctions;
using Amazon.StepFunctions.Model;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

namespace Unicorn.Properties.PropertiesService;

/// <summary>
/// Represents the AWS Lambda function that processes stream events from the
/// Unicorn Properties Contract Status table
/// </summary>
public class PropertiesApprovalSyncFunction
{
    private readonly AmazonStepFunctionsClient _amazonStepFunctionsClient;
    private readonly IDynamoDBContext _dynamoDbContext;

    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    public PropertiesApprovalSyncFunction()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();

        // Initialise DynamoDB client
        var dynamodbTable = Environment.GetEnvironmentVariable("CONTRACT_STATUS_TABLE");
        if (string.IsNullOrEmpty(dynamodbTable))
        {
            throw new Exception("Environment variable CONTRACT_STATUS_TABLE is not defined.");
        }

        AWSConfigsDynamoDB.Context.TypeMappings[typeof(ContractStatusItem)] =
            new TypeMapping(typeof(ContractStatusItem), dynamodbTable);

        var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
        _dynamoDbContext = new DynamoDBContext(new AmazonDynamoDBClient(), config);

        // Initialise Step Functions client
        _amazonStepFunctionsClient = new AmazonStepFunctionsClient();
    }

    /// <summary>
    /// Testing constructor
    /// </summary>
    /// <param name="mockStepFunctionsClient"></param>
    /// <param name="mockDynamoDbContext"></param>
    public PropertiesApprovalSyncFunction(AmazonStepFunctionsClient mockStepFunctionsClient,
        IDynamoDBContext mockDynamoDbContext)
    {
        _dynamoDbContext = mockDynamoDbContext;
        _amazonStepFunctionsClient = mockStepFunctionsClient;
    }

    /// <summary>
    /// Event handler for processing DynamoDB stream data for changes to Contract Status
    /// </summary>
    /// <param name="dynamoEvent">Instance of <see cref="DynamoDBEvent"/></param>
    /// <param name="context">Lambda Context runtime methods and attributes</param>
    [Logging(LogEvent = true)]
    [Metrics(CaptureColdStart = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public async Task FunctionHandler(DynamoDBEvent dynamoEvent, ILambdaContext context)
    {
        // process DDB
        foreach (var record in dynamoEvent.Records)
        {
            var propertyId = record.Dynamodb.Keys["PropertyId"].S;
            var item = await GetContractStatusItem(propertyId).ConfigureAwait(false);
            
            if (string.IsNullOrEmpty(item.SfnWaitApprovedTaskToken))
            {
                Logger.LogInformation("Contract status has no approval token, nothing to sync");
                return;
            }

            if (item.ContractStatus != "APPROVED")
            {
                Logger.LogInformation("Contract status for property is not APPROVED, cannot sync.");
                return;
            }

            if (item.ContractStatus == "APPROVED")
            {
                var sendTaskSuccessRequest = new SendTaskSuccessRequest
                {
                    TaskToken = item.SfnWaitApprovedTaskToken,
                    Output = JsonSerializer.Serialize(item)
                };

                try
                {
                    await _amazonStepFunctionsClient.SendTaskSuccessAsync(sendTaskSuccessRequest).ConfigureAwait(false);
                }
                catch (Exception e)
                {
                    Logger.LogError(e);
                    throw;
                }
            }
            else
            {
                Logger.LogInformation("Contract status for property is not APPROVED, cannot sync.");
                return;
            }
        }

        Logger.LogInformation("Property approval sync complete.");
    }

    /// <summary>
    /// Retrieves the contract status for a specifies property
    /// </summary>
    /// <param name="propertyId">Property ID</param>
    /// <returns>Instance of <see cref="ContractStatusItem"/></returns>
    /// <exception cref="ContractStatusNotFoundException"></exception>
    [Tracing(SegmentName = "Get Contract Status")]
    private async Task<ContractStatusItem> GetContractStatusItem(string propertyId)
    {
        ContractStatusItem? item;
        try
        {
            Logger.LogInformation($"Getting Contract Status for {propertyId}");
            item = await _dynamoDbContext.LoadAsync<ContractStatusItem>(propertyId).ConfigureAwait(false);
            Logger.LogInformation($"Found contact: {item != null}");
        }
        catch (Exception e)
        {
            Logger.LogInformation($"Error loading contract status {propertyId}: {e.Message}");
            item = null;
        }
       
        if (item == null)
        {
            throw new ContractStatusNotFoundException($"Could not find property with ID: {propertyId}");
        }

        return item;
    }
}