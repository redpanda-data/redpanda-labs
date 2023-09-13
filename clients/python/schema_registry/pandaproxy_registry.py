import requests
import json

class SchemaRegistry:
    def __init__(self, uri):
        self.base_uri = uri
    
    def publish(self, schema, subject=None):
        ''' Create a new schema for the subject.

        Keyword arguments:
        schema  -- Avro schema (JSON) to store in the schema registry
        subject -- Subject to identify the schema (default uses Avro schema name)
        '''
        if subject == None:
            subject = schema['name']
        
        r = requests.post(
            url = f'{self.base_uri}/subjects/{subject}/versions',
            data = json.dumps({'schema': json.dumps(schema)}),
            headers={'Content-Type': 'application/vnd.schemaregistry.v1+json'})
        r.raise_for_status()
        return r.json()['id']

    def _get(self, resource):
        ''' Send GET request to schema registry 
        
        Keyword arguments:
        resouce -- Schema registry endpoint:
                   https://app.swaggerhub.com/apis/BenPope/pandaproxy-schema-registry/0.0.4
        '''
        r = requests.get(f'{self.base_uri}{resource}')
        r.raise_for_status()
        return r.json()

    def get_schema(self, id):
        ''' Get a schema by id.

        Keyword arguments:
        id -- Schema id
        '''
        r = self._get(f'/schemas/ids/{id}')
        return r['schema']

    def get_schema_version(self, subject, version=None):
        ''' Retrieve a schema for the subject and version.

        Keyword arguments:
        subject -- Subject to identify the schema
        version -- Version of the schema to retrieve (default latest)
        '''

        resource = f'/subjects/{subject}/versions/latest'
        if version:
            resource = f'/subjects/{subject}/versions/{version}'
        r = self._get(resource)
        return r['schema']

    def list_subjects(self):
        ''' Retrieve a list of subjects. '''
        return self._get('/subjects')

    def get_versions(self, subject):
        ''' Retrieve a list of versions for a subject. 

        Keyword arguments:
        subject -- Subject to identify the schema
        '''
        return self._get(f'/subjects/{subject}/versions')
