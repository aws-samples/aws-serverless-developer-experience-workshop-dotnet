// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

using Amazon;
using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.Lambda.CloudWatchEvents;
using Amazon.Lambda.Core;
using Amazon.Util;
using Amazon.XRay.Recorder.Handlers.AwsSdk;
using AWS.Lambda.Powertools.Logging;
using AWS.Lambda.Powertools.Metrics;
using AWS.Lambda.Powertools.Tracing;
using Unicorn.Web.Common;
using DynamoDBContextConfig = Amazon.DynamoDBv2.DataModel.DynamoDBContextConfig;

namespace Unicorn.Web.ApprovalService;

public class PublicationApprovedEventHandler
{
    private readonly IDynamoDBContext _dynamoDbContext;
    
    /// <summary>
    /// Default constructor. Initialises global variables for function.
    /// </summary>
    /// <exception cref="Exception">Init exception</exception>
    public PublicationApprovedEventHandler()
    {
        // Instrument all AWS SDK calls
        AWSSDKHandler.RegisterXRayForAllServices();
        
        var dynamodbTable = Environment.GetEnvironmentVariable("DYNAMODB_TABLE") ?? "";
        if (string.IsNullOrEmpty(dynamodbTable))
            throw new Exception("Environment variable DYNAMODB_TABLE is not defined.");
        
        AWSConfigsDynamoDB.Context.TypeMappings[typeof(PropertyRecord)] =
            new TypeMapping(typeof(PropertyRecord), dynamodbTable);

        _dynamoDbContext = new DynamoDBContextBuilder()
            .ConfigureContext(c => c.Conversion=DynamoDBEntryConversion.V2)
            .Build();
    }

    /// <summary>
    /// Event handler for PublicationApprovedEvent
    /// </summary>
    /// <param name="publicationApprovedEvent">EventBridge event that triggers this function</param>
    /// <param name="context">Lambda Context runtime methods and attributes</param>
    [Logging(LogEvent = true)]
    [Metrics(CaptureColdStart = true)]
    [Tracing(CaptureMode = TracingCaptureMode.ResponseAndError)]
    public async Task FunctionHandler(CloudWatchEvent<PublicationApprovedEvent> publicationApprovedEvent, ILambdaContext context)
    {
        try
        {
            await PublicationApproved(publicationApprovedEvent.Detail);
        }
        catch (Exception e)
        {
            Logger.LogError(e);
            throw new PublicationApprovedEventHandlerException(e.Message);
        }
    }

    [Tracing(SegmentName = "Publication Approved")]
    private async Task PublicationApproved(PublicationApprovedEvent publicationApproved)
    {
        Logger.LogInformation($"Updating publication status for Property ID: {publicationApproved.PropertyId}");

        var splitString = publicationApproved.PropertyId.Split('/');
        var country = splitString[0];
        var city = splitString[1];
        var street = splitString[2];
        var number = splitString[3];

        var pk = PropertyRecordHelper.GetPartitionKey(country, city);
        var sk = PropertyRecordHelper.GetSortKey(street, number);

        Logger.LogInformation($"Loading the property from DynamoDB with PK {pk} and SK {sk}");
        var existingProperty = await _dynamoDbContext.LoadAsync<PropertyRecord>(pk, sk);

        if (string.Equals(publicationApproved.EvaluationResult, PropertyStatus.Approved, StringComparison.CurrentCultureIgnoreCase))
        {
            existingProperty.Status = PropertyStatus.Approved;
        }
        else if (string.Equals(publicationApproved.EvaluationResult, PropertyStatus.Declined, StringComparison.CurrentCultureIgnoreCase))
        {
            existingProperty.Status = PropertyStatus.Declined;
        }
        else
        {
            Logger.LogInformation($"evaluation_result: {publicationApproved.EvaluationResult} is not valid");
            return;
        }

        Logger.LogInformation($"Storing the evaluation result {existingProperty.Status} for property in DynamoDB with PK {pk} and SK {sk}");
        await _dynamoDbContext.SaveAsync(existingProperty);

        Metrics.AddMetric("PropertiesApproved", 1, MetricUnit.Count);
    }
}