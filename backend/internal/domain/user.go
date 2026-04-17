package domain

type Tenant struct {
	ID      string `json:"id"`
	Active  bool   `json:"active"`
	Nome    string `json:"nome"`
	Contato string `json:"contato,omitempty"`
	Plano   string `json:"plano,omitempty"`
	SchemaName string `json:"schema_name,omitempty"`
}

type User struct {
	ID       string `json:"id"`
	Nome     string `json:"nome"`
	Email    string `json:"email"`
	TenantID string `json:"tenantid"`
	Password string `json:"-"`
	Role     string `json:"role"`
	Active   bool   `json:"active,omitempty"`
	Tenant   Tenant `json:"tenant"`
}

type UserDetailTenant struct {
	ID         string `json:"id"`
	Active     bool   `json:"active"`
	Nome       string `json:"nome"`
	SchemaName string `json:"schema_name,omitempty"`
}

type UserDetailResult struct {
	ID       string           `json:"id"`
	Nome     string           `json:"nome"`
	Email    string           `json:"email"`
	Active   bool             `json:"active"`
	TenantID string           `json:"tenantId"`
	Role     string           `json:"role"`
	Tenant   UserDetailTenant `json:"tenant"`
}

type UserDetailEntry struct {
	Resultado UserDetailResult `json:"resultado"`
}

type UserDetailResponse struct {
	Usuarios []UserDetailEntry `json:"usuarios"`
}

type UserRoleData struct {
	ID       string `json:"id"`
	Email    string `json:"email"`
	TenantID string `json:"tenantid"`
	Role     string `json:"role"`
}

type UserRoleResponse struct {
	Logado UserRoleData `json:"logado"`
}

type UserTenantIDResponse struct {
	TenantID string `json:"tenantid"`
}

type UserListItem struct {
	ID         string `json:"id"`
	Nome       string `json:"nome"`
	Email      string `json:"email"`
	Role       string `json:"role"`
	TenantID   string `json:"tenantid"`
	TenantNome string `json:"tenantnome,omitempty"`
	Active     bool   `json:"active"`
}
