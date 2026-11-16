import { Routes } from '@angular/router';
import { LoginComponent } from './features/auth/login.component';
import { LayoutComponent } from './shared/layout/layout.component';
import { DashboardComponent } from './features/dashboard/dashboard.component';
import { EmployeesComponent } from './features/employees/employees.component';
import { PayrollComponent } from './features/payroll/payroll.component';
import { LeavesComponent } from './features/leaves/leaves.component';
import { MyPayslipsComponent } from './features/my-payslips/my-payslips.component';
import { MyProfileComponent } from './features/my-profile/my-profile.component';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
    { path: 'login', component: LoginComponent },
    {
        path: '',
        component: LayoutComponent,
        canActivate: [authGuard],
        children: [
            { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
            { path: 'dashboard', component: DashboardComponent },
            { path: 'employees', component: EmployeesComponent },
            { path: 'payroll', component: PayrollComponent },
            { path: 'declarations', loadComponent: () => import('./features/declarations/declarations.component').then((m) => m.DeclarationsComponent) },
            { path: 'leaves', component: LeavesComponent },
            { path: 'my-payslips', component: MyPayslipsComponent },
            { path: 'my-profile', component: MyProfileComponent },
            { path: 'profile-changes', loadComponent: () => import('./features/profile-changes/profile-changes.component').then((m) => m.ProfileChangesComponent) },
            { path: 'admin/tax-rules', loadComponent: () => import('./features/tax-rules/tax-rules.component').then((m) => m.TaxRulesComponent) },
            { path: 'admin/settings', loadComponent: () => import('./features/org-settings/org-settings.component').then((m) => m.OrgSettingsComponent) },
            { path: 'admin/roles', loadComponent: () => import('./features/admin-roles/admin-roles.component').then((m) => m.AdminRolesComponent) },
            { path: 'admin/users', loadComponent: () => import('./features/admin-users/admin-users.component').then((m) => m.AdminUsersComponent) },
            { path: 'me/security', loadComponent: () => import('./features/security/security.component').then((m) => m.SecurityComponent) }
        ]
    },
    { path: '**', redirectTo: 'login' }
];